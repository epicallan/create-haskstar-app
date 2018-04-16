{-# LANGUAGE OverloadedStrings #-}

module DBConfig where

import qualified Data.Text   as T
import           Interactive
import           Text.Regex
import           Turtle

data DBConfig =
  DBConfig
    {host       :: T.Text
    ,port       :: Integer
    ,dbName     :: T.Text
    ,dbUser     :: T.Text
    ,dbPassword :: T.Text
    ,dbSchema   :: T.Text
    }


mkDBConfig :: Text -> DBConfig
mkDBConfig appName =
    DBConfig
      {host = "localhost"
      ,port = 6543
      ,dbName = T.replace "-" "_" appName
      ,dbUser = "postgres"
      ,dbPassword = "postgres"
      ,dbSchema = "public"
      }

showDBInfo :: DBConfig -> IO ()
showDBInfo (DBConfig host port dbName dbUser dbPassword dbSchema) =
  subCommentBlock $ "Spinning up a local db instance in Docker with DB name " <> dbName <> " on port " <> (T.pack $ show port) <> " with username " <> dbUser <> " and password " <> dbPassword


textForDBEnvFile :: DBConfig -> Turtle.FilePath -> T.Text
textForDBEnvFile (DBConfig host port dbName dbUser dbPassword dbSchema) backendDir =
  T.intercalate "\n" $
         [ dbDatabaseLn dbName
         , dbUserLn dbUser
         , dbPasswordLn dbPassword
         , dbPortLn port
         ]
  where
    dbPasswordLn password = "POSTGRES_PASSWORD=" <> dbPassword
    dbDatabaseLn dbName   = "POSTGRES_DB=" <> dbName
    dbUserLn dbUser = "POSTGRES_USER=" <> dbUser
    dbPortLn dbPort = T.pack $ "POSTGRES_PORT=" <> show port
