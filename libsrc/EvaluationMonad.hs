{- DATX02-17-26, automated assessment of imperative programs.
 - Copyright, 2017, see AUTHORS.md.
 -
 - This program is free software; you can redistribute it and/or
 - modify it under the terms of the GNU General Public License
 - as published by the Free Software Foundation; either version 2
 - of the License, or (at your option) any later version.
 -
 - This program is distributed in the hope that it will be useful,
 - but WITHOUT ANY WARRANTY; without even the implied warranty of
 - MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 - GNU General Public License for more details.
 -
 - You should have received a copy of the GNU General Public License
 - along with this program; if not, write to the Free Software
 - Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 -}

{-# LANGUAGE GeneralizedNewtypeDeriving, FlexibleInstances #-}
module EvaluationMonad (
  liftIO,
  throw,
  catch,
  logMessage,
  withTemporaryDirectory,
  inTemporaryDirectory,
  issue,
  comment,
  EvalM,
  runEvalM,
  executeEvalM,
  Env(..),
  defaultEnv,
  parseEnv 
) where
import Control.Monad.Trans.Class
import Control.Monad.Trans.Except as E
import Control.Monad.Writer.Lazy hiding ((<>))
import Control.Monad.Reader
import Control.Monad.Morph
import qualified Control.Exception as Exc
import System.Exit
import System.Directory
import Options.Applicative
import Data.Semigroup hiding (option)

-- | A monad for evaluating student solutions
newtype EvalT m a = EvalT { unEvalT :: ExceptT EvalError (ReaderT Env (WriterT Feedback (WriterT Log m))) a }
  deriving (Monad, Applicative, Functor, MonadReader Env)

-- | Type-alias, in order to not break existing code
type EvalM a = EvalT IO a

-- | Very annoying monad transformer instance
instance MonadTrans EvalT where
  lift = EvalT . lift . lift . lift . lift

-- | Even more annoying MFunctor instance
instance MFunctor EvalT where
  hoist f = EvalT . (hoist (hoist (hoist (hoist f)))) . unEvalT

-- | For now we just log strings
type LogMessage = String
type Log        = [LogMessage]

-- | Evaluation errors are also just strings
type EvalError  = String

-- | Feedback generated for the student
data Feedback = Feedback { comments :: [String]
                         , issues   :: [String]
                         }

-- | Feedback is a monoid
instance Monoid Feedback where
  mempty        = Feedback [] []

  f `mappend` g = Feedback { comments = comments f ++ comments g
                           , issues   = issues f ++ issues g
                           }

-- | Pretty print feedback for the instructor
printFeedback :: Feedback -> String
printFeedback f = init
                $ unlines
                $  ["Comments:"]
                ++ (number $ comments f)
                ++ ["", "Issues:"]
                ++ (number $ issues f)
  where
    number xs = [show i ++ ". " ++ x | (x, i) <- zip xs [0..]]

-- | The environment of the program
data Env = Env { verbose       :: Bool
               , logfile       :: FilePath
               , numberOfTests :: Int
               }
  deriving Show

-- | The default environment
defaultEnv :: Env
defaultEnv = Env { verbose       = False
                 , logfile       = "logfile.log"
                 , numberOfTests = 100
                 }

-- | A parser for environments
parseEnv :: Parser Env
parseEnv =  Env
        <$> switch
              (  long    "verbose"
              <> short   'v'
              <> help    "Prints log messages during execution"
              )
        <*> strOption
              (  long    "logfile"
              <> short   'l'
              <> value   "logfile.log"
              <> metavar "LOGFILE"
              <> help    "Logfile produced on program crash"
              )
        <*> option auto
              (  long    "numTests"
              <> short   'n'
              <> value   100
              <> metavar "NUM_TESTS"
              <> help    "Number of tests during property based testing"
              )

-- | `printLog log` converts the log to a format suitable
-- for logfiles
printLog :: Log -> String
printLog = unlines

-- | Log a message
logMessage :: LogMessage -> EvalM ()
logMessage l = do
  EvalT $ (lift . lift . lift) $ tell [l]
  verb <- verbose <$> ask
  if verb then
    liftIO $ putStrLn l
  else
    return ()

-- | Generate a comment
comment :: (Monad m) => String -> EvalT m ()
comment c = EvalT $ (lift . lift) $ tell (Feedback [c] [])

-- | Generate an issue
issue :: (Monad m) => String -> EvalT m ()
issue i = EvalT $ (lift . lift) $ tell (Feedback [] [i])

-- | Throw an error
throw :: (Monad m) => EvalError -> EvalT m a
throw = EvalT . throwE

-- | Catch an error
catch :: (Monad m) => EvalT m a -> (EvalError -> EvalT m a) -> EvalT m a
catch action handler = EvalT $ catchE (unEvalT action) (unEvalT . handler)

-- | Lift an IO action and throw an exception if the
-- IO action throws an exception
performIO :: IO a -> EvalM a
performIO io = EvalT $ do
  result <- liftIO $ Exc.catch (Right <$> io) (\e -> return $ Left $ show (e :: Exc.SomeException))
  case result of
    Left err -> throwE err
    Right a  -> return a

-- | A `MonadIO` instance where
-- lifting means catching and rethrowing exceptions
instance MonadIO (EvalT IO) where
  liftIO = performIO

-- | Run an `EvalM` computation
runEvalM :: (Monad m) => Env -> EvalT m a -> m ((Either EvalError a, Feedback), Log)
runEvalM env = runWriterT . runWriterT . flip runReaderT env . runExceptT . unEvalT

-- | Execute an `EvalM logfile` computation, reporting
-- errors to the user and dumping the log to file
-- before exiting
executeEvalM :: Env -> EvalM a -> IO a
executeEvalM env eval = do
  ((result, feedback), log) <- runEvalM env eval
  case result of
    Left e -> do
      putStrLn $ "Error: " ++ e
      putStrLn $ "The log has been written to " ++ (logfile env)
      writeFile (logfile env) $ printLog log
      exitFailure
    Right a -> do
      putStrLn $ printFeedback feedback
      return a

-- | Run an `EvalM` computation with a temporary directory
withTemporaryDirectory :: FilePath -> EvalM a -> EvalM a
withTemporaryDirectory dir evalm = do
  liftIO $ createDirectoryIfMissing True dir
  result <- catch evalm $ \e -> liftIO (removeDirectoryRecursive dir) >> throw e 
  liftIO $ removeDirectoryRecursive dir
  return result

-- | Run an `EvalM` computation _in_ a temporary directory
inTemporaryDirectory :: FilePath -> EvalM a -> EvalM a
inTemporaryDirectory dir evalm = do
  was <- liftIO getCurrentDirectory

  logMessage $ "Changing directory to " ++ dir
  liftIO $ setCurrentDirectory dir
  result <- catch evalm $ \e -> liftIO (setCurrentDirectory was) >> throw e 

  logMessage $ "Changing directory to " ++ was
  liftIO $ setCurrentDirectory was
  return result
