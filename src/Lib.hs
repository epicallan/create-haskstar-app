#!/usr/bin/env runhaskell

{-# LANGUAGE OverloadedStrings #-}

module Lib where

import Turtle
import Filesystem.Path.CurrentOS (encodeString)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Interactive
import Context

askToRun :: IO () -> IO ()
askToRun onYes = do
  answer <- prompt "Setup Complete! Would you like to boot up the servers? (y) yes, (n) no" Nothing
  case answer of
     "y" -> onYes
     "n" -> echo "You can boot up each server by running ./run.sh"
     _ -> echo "Please entery (y) or (n)"

runServers :: Turtle.FilePath -> IO ()
runServers topDir = do
    runBackEnd topDir
    runFrontEnd topDir


data DirSetup =
  DirSetup
    {dirStackType :: DirStackType
    ,dirName :: Text
    ,gitDir :: Text
    }

data DirStackType = FRONT_END | BACK_END

frontendDirConfig :: DirSetup
frontendDirConfig =
  DirSetup
      {dirStackType = FRONT_END
      ,dirName = "front-end"
      ,gitDir = "git@github.com:smaccoun/haskstar-elm.git"
      }

backendDirConfig :: DirSetup
backendDirConfig =
  DirSetup
      {dirStackType = BACK_END
      ,dirName = "back-end"
      ,gitDir = "git@github.com:smaccoun/haskstar-haskell.git"
      }

asLocal dirName = "./" <> dirName




getDir :: Turtle.FilePath -> DirSetup -> (Text, Turtle.FilePath)
getDir rootDir dirSetup =
  (dname, dPath)
  where
    dname = dirName dirSetup
    dPath = rootDir </> (fromText dname)


setupDir :: DBConfig -> DirSetup -> App ()
setupDir dbConfig dirSetup = do
  appRootDir' <- getAppRootDir
  let (dname, dPath) = getDir appRootDir' dirSetup
  getTemplate dname dirSetup
  case dirStackType dirSetup of
    FRONT_END -> buildFrontEnd
    BACK_END -> buildBackEnd dbConfig


getTemplate :: Text -> DirSetup -> App ()
getTemplate dname dirSetup = do
  liftIO $ subCommentBlock $ "Setting up " <> dname
  fromAppRootDir
  setupResult <- shell ("git clone " <> gitDir dirSetup <> " " <> dname) empty
  case setupResult of
    ExitSuccess   -> return ()
    ExitFailure n -> die (" failed with exit code: " <> repr n)

buildFrontEnd :: App ()
buildFrontEnd = do
  topDir <- getAppRootDir
  liftIO $ subCommentBlock "Building front-end"
  let frontEndPath = getDir topDir frontendDirConfig & snd
  liftIO $ putStrLn $ encodeString frontEndPath
  cd frontEndPath
  _ <- shell "yarn install" empty
  _ <- shell "elm-package install --yes" empty
  return ()

buildBackEnd :: DBConfig -> App ()
buildBackEnd dbConfig = do
  liftIO $ subCommentBlock "Building back-end"
  fromAppRootDir
  topDir <- getAppRootDir
  let backendDir = getDir topDir backendDirConfig & snd
  cd backendDir
  _ <- shell "stack build" empty
  liftIO $ majorCommentBlock "SETUP DB CONFIGURATION"
  _ <- liftIO $ mkBackendEnv dbConfig backendDir
  return ()

data DBConfig =
  DBConfig
    {host :: T.Text
    ,port :: Int
    ,dbName :: T.Text
    ,dbUser :: T.Text
    ,dbPassword :: T.Text
    ,dbSchema :: T.Text
    }

getDBConfig :: IO DBConfig
getDBConfig = do
  instructionCommentBlock "First setup the DB configuration you would like"
  dbName <- prompt "Enter name of DB" Nothing
  dbSchema <- prompt "Enter default schema" (Just "public")
  dbUser <- prompt "Enter name of User" (Just "postgres")
  dbPassword <- prompt "Enter DB Password" (Just "postgres")
  return $
    DBConfig
      {host = "localhost"
      ,port = 5432
      ,dbName = dbName
      ,dbUser = dbUser
      ,dbPassword = dbPassword
      ,dbSchema = dbSchema
      }

setupDBDir :: DBConfig -> App ()
setupDBDir dbConfig = do
  liftIO $ majorCommentBlock "SETTING UP DB"
  rootDir <- getAppRootDir
  fromAppRootDir
  mkdir "db"
  cd "./db"
  let dbEnvFile = getDBEnvFile dbConfig rootDir
  liftIO $ writeTextFile ".env" dbEnvFile
  dockerRunResult <- shell dockerRunCmd empty
  case dockerRunResult of
    ExitSuccess   -> do
        liftIO $ instructionCommentBlock $ "\nSuccessfully booted docker instance.\n To log into the database run:" <> dockerRunCmd
        cd rootDir
        return ()
    ExitFailure n -> die ("Failed to boot docker instance for DB: " <> repr n)
  where
    dockerRunCmd = "docker run --name my-app-db  -p 5432:5432 -h 127.0.0.1 --env-file .env -d postgres"


getDBEnvFile :: DBConfig -> Turtle.FilePath -> T.Text
getDBEnvFile (DBConfig host port dbName dbUser dbPassword dbSchema) backendDir =
  T.intercalate "\n" $
         [ dbDatabaseLn dbName
         , dbUserLn dbUser
         , dbPasswordLn dbPassword
         ]
  where
    dbPasswordLn password = "POSTGRES_PASSWORD=" <> dbPassword
    dbDatabaseLn dbName   = "POSTGRES_DB=" <> dbName
    dbUserLn dbUser = "POSTGRES_USER=" <> dbUser


mkBackendEnv :: DBConfig -> Turtle.FilePath -> IO ()
mkBackendEnv (DBConfig host port dbName dbUser dbPassword dbSchema) backendDir = do
  let textFile = T.intercalate "\n" $
         [ dbHostLn
         , dbPortLn
         , dbDatabaseLn dbName
         , dbSchemaLn dbSchema
         , dbUserLn dbUser
         , dbPasswordLn dbPassword
         ]
  writeTextFile (backendDir </> ".env") textFile

  where
    dbHostLn    = "DB_HOST=localhost"
    dbPortLn    = "DB_PORT=5432"
    dbDatabaseLn dbName   = "DB_DATABASE=" <> dbName
    dbSchemaLn schema     = "DB_SCHEMA=" <> schema
    dbUserLn dbUser = "DB_USERNAME=" <> dbUser
    dbPasswordLn password = "DB_PASSWORD=" <> dbPassword


runFrontEnd :: Turtle.FilePath -> IO ()
runFrontEnd topDir = do
  majorCommentBlock "STARTING WEB SERVER"
  cd $ getDir topDir frontendDirConfig & snd
  s <- shell "../ttab yarn start " empty
  case s of
    ExitSuccess   -> do
        printf "\nSuccessfully started server. Go to localhost:3000\n"
        return ()
    ExitFailure n -> die (" failed with exit code: " <> repr n)
  return ()

runBackEnd :: Turtle.FilePath -> IO ()
runBackEnd topDir = do
  majorCommentBlock "STARTING LOCAL BACK-END"
  cd $ getDir topDir backendDirConfig & snd
  s <- shell "../ttab ./run.sh" empty

  case s of
    ExitSuccess   -> do
        printf "\nSuccessfully started api. Logs will be output to console\n"
        return ()
    ExitFailure n -> die (" failed with exit code: " <> repr n)
  return ()


