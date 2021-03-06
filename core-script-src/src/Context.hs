{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}

module Context where

import           Control.Lens              (view, (^.))
import           Control.Lens.TH
import           Control.Monad.Reader      (MonadReader, ReaderT, ask, asks)
import           Filesystem.Path.CurrentOS
import           GHC.Generics
import           Turtle

newtype ScriptRunContext a =
  ScriptRunContext {unScriptRunContext :: ReaderT Context IO a
  }
  deriving (
     Functor
     , Applicative
     , Monad
     , MonadReader Context
     , MonadIO
     )

newtype ExecutablePath = ExecutablePath { unExecutablePath :: Turtle.FilePath }

data Context =
  Context
    {_appRootDir :: Turtle.FilePath
    ,_exeRootDir :: ExecutablePath
    ,_mbTemplate :: Maybe Text
    }

makeClassy ''Context

data Environment = Local | RemoteEnv RemoteStage
data RemoteStage = Staging | Production
data StackLayer = Frontend | Backend


getAppRootDir :: (MonadReader r m, HasContext r)
              => m Turtle.FilePath
getAppRootDir =
  Control.Lens.view (context . appRootDir)

fromAppRootDir :: ScriptRunContext Turtle.FilePath
fromAppRootDir = do
  appRootDir <- getAppRootDir
  cd appRootDir
  return appRootDir

getOpsDir :: ScriptRunContext Turtle.FilePath
getOpsDir = do
  rdir <- getAppRootDir
  return $ rdir </> "ops"

getKubernetesDir :: ScriptRunContext Turtle.FilePath
getKubernetesDir = do
  opsDir' <- getOpsDir
  return $ opsDir' </> "kubernetes"

getTTab :: ScriptRunContext Turtle.FilePath
getTTab = do
  opsDir' <- getOpsDir
  return $ opsDir' </> "ttab"

getMbTemplate :: (MonadReader r m, HasContext r)
              => m (Maybe Text)
getMbTemplate = do
  Control.Lens.view (context . mbTemplate)

getWebStackDir :: (MonadReader r m, HasContext r)
              => String
              -> m Turtle.FilePath
getWebStackDir webStackDir = do
  rdir <- getAppRootDir
  return $ rdir </> decodeString webStackDir


getBackendDir :: (MonadReader r m, HasContext r)
              => m Turtle.FilePath
getBackendDir =
  getWebStackDir "back-end"


getFrontendDir :: (MonadReader r m, HasContext r)
              => m Turtle.FilePath
getFrontendDir =
  getWebStackDir "front-end"

getDBDir :: (MonadReader r m, HasContext r)
              => m Turtle.FilePath
getDBDir =
  getWebStackDir "db"




