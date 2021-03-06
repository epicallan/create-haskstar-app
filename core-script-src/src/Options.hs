#!/usr/bin/env runhaskell

{-# LANGUAGE OverloadedStrings #-}

module Options where

import           Context           (Environment (..), RemoteStage (..))
import           Lib               (SHA1 (..))
import           PostSetup.Config
import           PostSetup.Context
import           PostSetup.Deploy
import           Turtle

data ExecutionContext =
      New Text
    | PostSetupMode PostSetupOption

data PostSetupOption =
    Build BuildCmd
  | Start StartCmd
  | Run RunCmd
  | Deploy DeployConfig RemoteStage
  | Login LoginCmd
  | Configure Environment ConfigureCmd

data BuildCmd = BuildFrontEnd | BuildBackEnd | BuildAll
data StartCmd = StartAPI | StartWeb | StartDB
data RunCmd = RunMigrations Environment
data ConfigureCmd = ConfigureDB

data LoginCmd = LoginDB

parseCmd :: Parser ExecutionContext
parseCmd =
      fmap New (subcommand "new" "Setup new App" $ argText "appName" "Choose a name for your app")
  <|> fmap (\a -> PostSetupMode (Start a))
        (subcommand "start" "Start services" parseStartCmd)
  <|> fmap (\r -> PostSetupMode (Run r))
        (subcommand "run" "Run services" parseRunCmd)
  <|> fmap (\a -> PostSetupMode (Build a))
        (subcommand "build" "Build services" parseBuildCmd)
  <|> fmap mapDeployParse
        (subcommand "deploy" "Deploy services" parseDeployCmd)
  <|> fmap (\(e, c) -> PostSetupMode (Configure e c))
        (subcommand "configure" "Configure services" parseConfigureCmd)
  <|> fmap (\a -> PostSetupMode (Login a))
        (subcommand "login" "Login services" parseLoginCmd)
  where
    mapDeployParse :: (RemoteStage, Maybe Text, Maybe Text) -> ExecutionContext
    mapDeployParse (depEnv, sha1, remoteDockerDir) =
      PostSetupMode $ Deploy (mkDeployConfig sha1 remoteDockerDir) depEnv
    mkDeployConfig :: Maybe Text -> Maybe Text -> DeployConfig
    mkDeployConfig sha1 remoteDockerDir =
      DeployConfig
        {remoteDockerBaseDir = fmap RemoteDockerBaseDir remoteDockerDir
        ,sha1                = fmap SHA1 sha1
        }

parseStartCmd :: Parser StartCmd
parseStartCmd =
  arg parseStartText "startCmd" "Choose either 'frontend', 'backend', or 'db'"
  where
    parseStartText rt =
      case rt of
        "backend"  -> Just StartAPI
        "frontend" -> Just StartWeb
        "db"       -> Just StartDB
        _          -> Nothing

parseRunCmd :: Parser RunCmd
parseRunCmd =
  parseFirstArg <*> parseSecondArg
  where
    parseFirstArg :: Parser (Environment -> RunCmd)
    parseFirstArg =
      arg parseStartText "runCmd" "Choose 'migrations'"

    parseStartText :: Text -> Maybe (Environment -> RunCmd)
    parseStartText rt =
      case rt of
        "migrations" -> Just RunMigrations
        _            -> Nothing

    parseSecondArg :: Parser Environment
    parseSecondArg =
      arg parseEnv "runCmd" "Choose 'migrations'"

parseEnv :: Text -> Maybe Environment
parseEnv e =
  case e of
    "local"      -> Just Local
    "staging"    -> Just $ RemoteEnv Staging
    "production" -> Just $ RemoteEnv Production
    _            -> Nothing

parseLoginCmd :: Parser LoginCmd
parseLoginCmd =
  arg parseLoginText "loginCmd" "Choose 'db'"
  where
    parseLoginText rt =
      case rt of
        "db" -> Just LoginDB
        _    -> Nothing


parseDeployCmd :: Parser (RemoteStage, Maybe Text, Maybe Text)
parseDeployCmd =
  (,,)
  <$> arg parseDeployEnvText "deployCmd" "Choose either 'staging' or 'production'"
  <*> optional (optText "SHA1"  'a' "SHA1 Commit Number")
  <*> optional (optText "remoteDockerDir"  'a' "Remote Docker Dir")
  where
    parseDeployEnvText rt =
      case rt of
        "staging"    -> Just Staging
        "production" -> Just Production
        _            -> Nothing

parseBuildCmd :: Parser BuildCmd
parseBuildCmd =
  arg parseStartText "buildCmd" "Choose either 'frontend', 'backend', or 'migrations'"
  where
    parseStartText rt =
      case rt of
        "backend"  -> Just BuildBackEnd
        "frontend" -> Just BuildFrontEnd
        "all"      -> Just BuildAll
        _          -> Nothing


parseConfigureCmd :: Parser (Environment, ConfigureCmd)
parseConfigureCmd =
  (,)
  <$> arg parseEnvOption "env" "Choose either 'local', 'staging', or 'production'"
  <*> arg parseConfigCmd "config" "Choose db"
  where
    parseConfigCmd :: Text -> Maybe ConfigureCmd
    parseConfigCmd rt =
      case rt of
        "db" -> Just ConfigureDB
        _    -> Nothing

parseEnvOption :: Text -> Maybe Environment
parseEnvOption rt =
  case rt of
    "local"      -> Just Local
    "staging"    -> Just $ RemoteEnv Staging
    "production" -> Just $ RemoteEnv Production
    _            -> Nothing


parser :: Parser (ExecutionContext, Maybe Text, Maybe Text)
parser = (,,)
             <$> parseCmd
             <*> optional (optText "front-end"  'a' "Choice of front-end")
             <*> optional (optText "template"  'a' "Choice of template")
