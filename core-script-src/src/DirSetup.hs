#!/usr/bin/env runhaskell

{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module DirSetup where

import           Context
import           Control.Lens              ((^.))
import qualified Data.Aeson                as A
import qualified Data.ByteString.Lazy      as LBS
import           Data.Text                 (Text, intercalate, pack)
import qualified Data.Text                 as T
import           Data.Text.Encoding        (decodeUtf8)
import qualified Data.Text.Lazy            as TL
import           Data.Text.Lazy.Builder    (toLazyText)
import           DBConfig
import qualified Filesystem.Path           as FP
import           Filesystem.Path.CurrentOS (decodeString, encodeString)
import           GHC.Generics
import           Interactive
import           Lib
import           PostSetup.Config
import           Run                       (runDB)
import           Servant.Auth.Server       (generateKey)
import           Text.Mustache
import           Turtle


data FrontEndSetupConfig =
  FrontEndSetupConfig
    {frontEndLang         :: FrontEndLang
    ,frontEndBaseTemplate :: GitBaseTemplateUrl
    }

data FrontEndLang =
    Elm
  | GHCJS
    deriving (Generic, Show, A.FromJSON)

runSetup :: Text -> DBConfig -> ScriptRunContext ()
runSetup appName' dbConfig = do
  writeHASMFile hasmFile
  setupAllSubDirectories dbConfig
  where
    hasmFile =
      HASMFile
        {_appName = Just appName'
        ,_remote = RemoteConfig Nothing
        }



-- | Setup DB, Front-End, Back-End directories without building them
setupCoreDirectories :: DBConfig -> ScriptRunContext ()
setupCoreDirectories dbConfig = do
  appDir <- getAppRootDir
  majorCommentBlock "DB"
  setupDBDir dbConfig
  majorCommentBlock "BACK-END"
  setupBackendDir dbConfig
  majorCommentBlock "FRONT-END"
  setupFrontendDir elmFrontEndSetupConfig

setupAllSubDirectories :: DBConfig -> ScriptRunContext ()
setupAllSubDirectories dbConfig = do
  setupOpsDir
  setupCoreDirectories dbConfig

setupBackendDir :: DBConfig -> ScriptRunContext ()
setupBackendDir dbConfig = do
  cloneTemplateAsDir backendBaseGitUrl (CoreStackDirName "back-end")
  mkBackendEnv dbConfig
  return ()
  where
    backendBaseGitUrl = GitBaseTemplateUrl "https://github.com/smaccoun/haskstar-haskell"

setupFrontendDir :: FrontEndSetupConfig -> ScriptRunContext ()
setupFrontendDir frc@(FrontEndSetupConfig _ gitBaseUrl ) = do
  cloneTemplateAsDir gitBaseUrl (CoreStackDirName "front-end")
  buildFrontendBaseLibraries frc
  return ()

buildFrontendBaseLibraries :: FrontEndSetupConfig -> ScriptRunContext ()
buildFrontendBaseLibraries _ = do
  --TODO: Handle GHCJS initial compile case
  frontendDir <- getFrontendDir
  cd frontendDir
  _ <- shell "yarn install" empty
  _ <- shell "elm-package install --yes" empty
  return ()

mkBackendEnv :: DBConfig -> ScriptRunContext ()
mkBackendEnv (DBConfig host port dbName dbUser dbPassword dbSchema) = do
  jwkKey <- liftIO generateKey
  let textFile = T.intercalate "\n" $
         [ dbHostLn
         , T.pack $ dbPortLn port
         , dbDatabaseLn dbName
         , dbSchemaLn dbSchema
         , dbUserLn dbUser
         , dbPasswordLn dbPassword
         , jwkLine jwkKey
         ]
  backendDir <- getBackendDir
  liftIO $ writeTextFile (backendDir </> ".env") textFile
  return ()

  where
    dbHostLn    = "DB_HOST=localhost"
    dbPortLn dbPort = "DB_PORT=" <> show dbPort
    dbDatabaseLn dbName   = "DB_DATABASE=" <> dbName
    dbSchemaLn schema     = "DB_SCHEMA=" <> schema
    dbUserLn dbUser = "DB_USERNAME=" <> dbUser
    dbPasswordLn password = "DB_PASSWORD=" <> dbPassword
    jwkLine jwkKey = "AUTH_JWK=" <> (T.replace "\"" "\\\"" . decodeUtf8 . LBS.toStrict . A.encode $ jwkKey)


setupDBDir :: DBConfig -> ScriptRunContext ()
setupDBDir dbConfig = do
  liftIO $ majorCommentBlock "SETTING UP DB"
  dbDir <- getDBDir
  opsDir' <- getOpsDir
  let templateMigrationPackage = (fmap decodeString) ["db", "migrations", "haskell",  "pg-simple"] & FP.concat
      simpleMigrationDir = opsDir' </> templateMigrationPackage
  cptree simpleMigrationDir dbDir
  cd dbDir
  let dbEnvFile = textForDBEnvFile dbConfig
  liftIO $ writeTextFile ".env" dbEnvFile

  _ <- shell "stack build" empty
  runDB



setupOpsDir :: ScriptRunContext ()
setupOpsDir = do
  setupOpsTree
  configureDeploymentScripts

setupOpsTree :: ScriptRunContext ()
setupOpsTree = do
    fromAppRootDir
    topDir <- getAppRootDir
    mbTemplate <- getMbTemplate
    kubernetesDir <- getKubernetesDir
    liftIO $ do
      majorCommentBlock "Grabbing required templates"
      mktree "./ops/db"
      _ <- gitCloneShallow "git@github.com:smaccoun/create-haskstar-app.git" mbTemplate
      cptree "./create-haskstar-app/templates/ops" "./ops"
      cptree "./create-haskstar-app/templates/db" "./ops/db"
      cptree "./create-haskstar-app/templates/kubernetes" kubernetesDir
      let circleDir = topDir </> ".circleci"
      mkdir circleDir
      cptree "./ops/ci/.circleci/" circleDir
      rmtree "create-haskstar-app"

getKubernetesDir :: ScriptRunContext Turtle.FilePath
getKubernetesDir = do
  opsDir' <- getOpsDir
  return $ opsDir' </> "kubernetes"

configureDeploymentScripts :: ScriptRunContext ()
configureDeploymentScripts = do
  configureBackendServiceFile
  configureBackendDeploymentFile
  configureFrontendDeploymentFile
  return ()


configureDeploymentFile :: Text -> A.Value -> ScriptRunContext ()
configureDeploymentFile mustacheFileName jsonValue = do
  kubernetesDir <- getKubernetesDir
  let backendStacheFile = kubernetesDir </> fromText mustacheFileName
  hasmFile <- readHASMFile
  backendStacheTemplate <- compileMustacheFile $ encodeString backendStacheFile
  let writeToFilename = T.replace ".mustache" "" mustacheFileName
      backendServiceYamlPath = kubernetesDir </> fromText writeToFilename
  _ <- liftIO $ writeTextFile backendServiceYamlPath
              $ TL.toStrict
              $ renderMustache backendStacheTemplate jsonValue
  rm backendStacheFile
  return ()

configureBackendDeploymentFile :: ScriptRunContext ()
configureBackendDeploymentFile = do
  hasmFile <- readHASMFile
  let decoder =
          A.object
            [ "appName" A..= (hasmFile ^. appName)
            , "remoteDockerImage" A..= (hasmFile ^. remote ^. dockerImage)
          ]
  configureDeploymentFile "backend-deployment.yaml.mustache" decoder

configureFrontendDeploymentFile :: ScriptRunContext ()
configureFrontendDeploymentFile = do
  hasmFile <- readHASMFile
  let decoder =
          A.object
            [ "appName" A..= (hasmFile ^. appName)
            , "remoteDockerImage" A..= (hasmFile ^. remote ^. dockerImage)
          ]
  configureDeploymentFile "frontend.yaml.mustache" decoder


configureBackendServiceFile :: ScriptRunContext ()
configureBackendServiceFile = do
  hasmFile <- readHASMFile
  let decoder =
          A.object
            [ "appName" A..= (hasmFile ^. appName)
          ]
  configureDeploymentFile "backend-service.yaml.mustache" decoder



newtype GitBaseTemplateUrl = GitBaseTemplateUrl Text
newtype CoreStackDirName =  CoreStackDirName Text

cloneTemplateAsDir :: GitBaseTemplateUrl -> CoreStackDirName -> ScriptRunContext ()
cloneTemplateAsDir (GitBaseTemplateUrl gitUrl) (CoreStackDirName dirName) = do
  liftIO $ subCommentBlock $ "Setting up " <> dirName
  appRootDir <- fromAppRootDir
  mbTemplate <- getMbTemplate
  setupResult <- liftIO $ gitCloneShallow (gitUrl <> " " <> dirName) mbTemplate
  case setupResult of
    ExitSuccess   -> do
      liftIO $ rmtree (fromText dirName </> fromText ".git")
      return ()
    ExitFailure n -> die (" failed with exit code: " <> repr n)



--TODO: Read this in from config file
elmFrontEndSetupConfig :: FrontEndSetupConfig
elmFrontEndSetupConfig =
  FrontEndSetupConfig
    {frontEndLang = Elm
    ,frontEndBaseTemplate = GitBaseTemplateUrl "git@github.com:smaccoun/haskstar-elm.git"
    }
