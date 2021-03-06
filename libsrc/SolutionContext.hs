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
{-# LANGUAGE TemplateHaskell #-}
module SolutionContext where
import System.Directory
import Control.Monad.Trans.State
import System.FilePath

import EvaluationMonad

-- | The context in which we are investigating a student solution
data SolutionContext a = Ctx { studentSolution :: a
                             , modelSolutions  :: [a]
                             }
                             deriving (Eq, Show, Ord)

-- | `Context` is a functor, obviously
instance Functor SolutionContext where
  fmap f (Ctx ss ms) = Ctx (f ss) (f <$> ms)

-- | Get the file path of student and model solutions
getFilePathContext :: FilePath -> FilePath -> EvalM (SolutionContext FilePath)
getFilePathContext studentPath modelDir = do
  -- Check if the student solution exists
  logMessage $ "Checking if " ++ studentPath ++ " exists"
  exists <- liftIO $ doesFileExist studentPath

  if exists then
    return ()
  else
    throw $ "Couldn't read student solution from: " ++ studentPath

  -- Get the .java files in the model solution directory
  logMessage $ "Checking for model solutions in directory \"" ++ modelDir ++ "\""

  modelDirJavaFiles <- liftIO $ filter ((".java" ==) . takeExtension) <$> listDirectory modelDir 

  logMessage $ "Found the following model solutions in directory \"" ++ modelDir ++ "\":\n" ++ init (unlines modelDirJavaFiles)

  return $ Ctx studentPath (combine modelDir <$> modelDirJavaFiles)

-- | Read the contents from the student and model solution paths
readRawContents :: SolutionContext FilePath -> EvalM (SolutionContext String)
readRawContents ctx = do
  -- Do some logging
  logMessage $ "Reading student solution"

  -- Read the student solution
  studentSolution <- liftIO $ readFile $ studentSolution ctx

  -- Do some more logging
  logMessage $ "Reading model solutions"

  -- Get the contents of the model solutions
  modelSolutions <- liftIO $ sequence $ readFile <$> modelSolutions ctx

  -- Return the contest
  return $ Ctx studentSolution modelSolutions

-- | Check if a student solution matches any of the model solutions
studentSolutionMatches :: (a -> a -> Bool) -> SolutionContext (FilePath, a) -> EvalM (Maybe FilePath)
studentSolutionMatches eqCheck ctx = go (modelSolutions ctx)
  where
    studSol = snd (studentSolution ctx)

    go []             = return Nothing
    go ((fp, modSol):sols)  = do
      logMessage $ "Checking: " ++ fp
      if eqCheck studSol modSol
      then return (Just fp)
      else go sols

-- | Zip together two SolutionContext's
zipContexts :: SolutionContext a -> SolutionContext b -> SolutionContext (a, b)
zipContexts (Ctx a as) (Ctx b bs) = Ctx (a, b) (zip as bs)
