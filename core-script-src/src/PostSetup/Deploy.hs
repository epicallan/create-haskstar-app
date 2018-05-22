#!/usr/bin/env runhaskell

{-# LANGUAGE OverloadedStrings #-}

module PostSetup.Deploy where

import           Context
import           Control.Lens
import           Data.Text                 (pack)
import qualified Data.Text                 as T (lines)
import           DirSetup                  (configureDeploymentFile)
import           Filesystem.Path.CurrentOS (encodeString)
import           Interactive
import           Lib
import           PostSetup.Config
import           PostSetup.Context         (DeployConfig (..),
                                            RemoteDockerBaseDir (..))
import           PostSetup.K8
import           PostSetup.Run             (runMigrations)
import           Turtle

deploy :: DeployConfig -> ScriptRunContext ()
deploy deployConfig = do
  deployBackend
  deployFrontend
  runMigrations $ RemoteEnv Production
  return ()


deployBackend :: ScriptRunContext ExitCode
deployBackend = do
  appName' <- getAppName
  dbConfig <- readDBConfig $ RemoteEnv Production --TODO: Make env specific
  _ <- configureKubeSecrets appName' dbConfig
  runK8Cmd $ SetImage Backend

deployFrontend :: ScriptRunContext ExitCode
deployFrontend = do
  runK8Cmd $ SetImage Frontend

getShaToDeploy :: Maybe SHA1 -> ScriptRunContext SHA1
getShaToDeploy mbSha1 =
  case mbSha1 of
    Nothing -> do
      sha1Line <- Turtle.strict $ single (inshell "git rev-parse HEAD" empty)
      let sha1Text = head $ T.lines sha1Line
      return $ SHA1 sha1Text
    Just sha1 ->
      return sha1

runK8Cmd :: K8Commands -> ScriptRunContext ExitCode
runK8Cmd kubeAction = do
  fromAppRootDir
  kubeStrCmd <- getKubeAction kubeAction
  let command =  baseKubeCmdStr kubeStrCmd
  printfln $ "Running \"" <> command <> "\""
  liftIO $ shell command empty

baseKubeCmdStr :: Text -> Text
baseKubeCmdStr cmdStr =
  "kubectl " <> cmdStr


getKubeAction :: K8Commands -> ScriptRunContext Text
getKubeAction kubeAction =
  case kubeAction of
    SetImage stackLayer -> do
      sha1 <- getShaToDeploy Nothing
      deploymentFile <- configureDeploymentFile stackLayer sha1
      return $ " apply -f " <> (pack . encodeString $ deploymentFile)

getK8ContainerName :: StackLayer -> ScriptRunContext Text
getK8ContainerName stackLayer = do
  appName <- getAppName
  return $ appName <> "-" <> dep
  where
    dep =
      case stackLayer of
        Backend  -> "backend"
        Frontend -> "frontend"

k8DeploymentName :: StackLayer -> ScriptRunContext Text
k8DeploymentName stackLayer = do
  k8Container <- getK8ContainerName stackLayer
  return $ "deployment/" <> k8Container


getRemoteDockerBaseDir :: DeployConfig -> ScriptRunContext Text
getRemoteDockerBaseDir (DeployConfig mbRemoteDockerBaseDir mbSHA1 ) =
  case mbRemoteDockerBaseDir of
    Just rd -> return $ tagRemoteDir rd mbSHA1
    Nothing -> do
      remoteConfig <- readRemoteConfig
      let remoteDockerImage = remoteConfig ^. dockerBaseImage
      return $ tagRemoteDir (RemoteDockerBaseDir remoteDockerImage) mbSHA1

tagRemoteDir :: RemoteDockerBaseDir -> Maybe SHA1 -> Text
tagRemoteDir (RemoteDockerBaseDir d) maybeSha1 =
    case maybeSha1 of
      Just (SHA1 sha1) -> d <> ":" <> sha1
      Nothing          -> d

dockerBuildStrCmd :: Text -> Turtle.FilePath -> Text
dockerBuildStrCmd remoteDockerDir localDockerFile =
  format ("docker build --rm=false -t "%s%" -f "%s%"") remoteDockerDir (pack $ encodeString localDockerFile)

dockerPushCmd :: Text -> Text
dockerPushCmd =
  format ("docker push "%s%"")

