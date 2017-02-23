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
module PropertyBasedTesting where

import System.FilePath
import System.Process
import System.Directory
import System.Timeout
import Control.Monad.Reader
import Test.QuickCheck

import InputMonad
import EvaluationMonad

-- | Get the output from the class file `file`
solutionOutput :: String -> FilePath -> EvalM String
solutionOutput stdin file = do
  let command = "java " ++ dropExtension file
  logMessage $ "Running the command: " ++ command

  -- Timeout 1 second
  m <- liftIO $ timeout 1000000 $ readCreateProcess (shell command) stdin
  case m of
    Nothing -> throw "Command timed out"
    Just x  -> return x

-- | Get the output of the student solution
studentOutput :: FilePath -> String -> EvalM (Maybe String)
studentOutput dir input = do
  -- This is really inefficient and should be floated to the top level
  ss <- liftIO $ listDirectory $ dir </> "student"
  studentSolutionName <- case ss of
                          []    -> throw "Student solution missing"
                          (s:_) -> return s
  catch (Just <$> (inTemporaryDirectory (dir </> "student") $ solutionOutput input studentSolutionName))
        (\_ -> issue "Student test timeout" >> return Nothing)

-- | Get the output of every model solution
modelSolutionsOutputs :: FilePath -> String -> EvalM [String]
modelSolutionsOutputs dir input = do
  modelSolutions <- liftIO $ listDirectory (dir </> "model")
  inTemporaryDirectory (dir </> "model") $ sequence $ solutionOutput input <$> modelSolutions

-- | Test the student solution in `dir </> "student/"` against
-- the solutions in `dir </> "model/"`
testSolutions :: FilePath -> String -> EvalM Bool
testSolutions dir input = do
  modelOutputs <- modelSolutionsOutputs dir input

  studO <- studentOutput dir input

  case studO of
    Just s  -> return $ or [s == output | output <- modelOutputs]
    Nothing -> return False

-- | Perform the relevant tests on all class files in the directory
-- `dir`, returns `True` if the student solution passes all tests
runPBT :: FilePath -> Gen String -> EvalM ()
runPBT dir generator = do
  numTests <- numberOfTests <$> ask
  logMessage $ "Testing student solution " ++ show numTests ++ " times"
  inner numTests
  where
    -- Ugly inner loop, this should be done more elequently
    inner 0 = comment "Student solution passed tests"
    inner n = do
      input  <- liftIO $ generate generator
      passed <- testSolutions dir input
      if passed then
        inner (n - 1)
      else
        issue $ "Student solution does not pass tests, fails on:\"\"\"\n" ++ input ++ "\"\"\""
