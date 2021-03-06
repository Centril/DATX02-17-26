module Main where

import System.Environment
import System.Directory
import System.FilePath
import qualified Control.Exception as Exc

import EvaluationMonad
import GenStrat
import SolutionContext
import NormalizationStrategies
import CoreS.AST
import qualified CoreS.ASTUnitype as AST
import CoreS.ASTUnitypeUtils
import CoreS.Parse
import Data.RoseTree
import Data.List
import Norm.AllNormalizations as ALL

import PropertyBasedTesting

main :: IO ()
main = do
  args <- getArgs
  case args of
    [stud, mods] -> do
      studs   <- map (stud </>) <$> filter hasExtension <$> listDirectory stud
      mods    <- map (mods </>) <$> filter hasExtension <$> listDirectory mods
      results <- mapM (\stud -> checkMatches stud mods) studs
      let trues = [ takeFileName x | (Just (x , True)) <- results ]
          all   = [ () | (Just _) <- results ]
          matched = length trues
          percent = 100 * (genericLength trues / genericLength all) :: Double
      putStrLn $ "Total number of student solutions: "      ++ show (length studs)
      putStrLn $ "Total number of kept student solutions: " ++ show (length all)
      putStrLn $ "Total number of model solutions: "        ++ show (length mods)
      putStrLn $ "Percentage matched: " ++ show percent
      putStrLn $ "Total matched: " ++ show matched
      putStrLn $ "Specific matched: " ++ show trues
    _ -> putStrLn "Bad args"

normalize :: CompilationUnit -> CompilationUnit
normalize = executeNormalizer ALL.normalizations

normalizeUAST :: AST.AST -> AST.AST
normalizeUAST  = AST.inCore normalize

checkMatches :: FilePath -> [FilePath] -> IO (Maybe (FilePath, Bool))
checkMatches stud mods = do
  let paths = Ctx stud mods
  Just (Ctx stud mods) <- Exc.catch
                            (Just <$> resultEvalM ((fmap parseConv) <$> readRawContents paths))
                            ((\e -> return Nothing `const` (e :: Exc.ErrorCall)) {-:: Exc.ErrorCall -> IO (Maybe (SolutionContext (CConv (Repr t))))-})
  case stud of
    Left _     -> return Nothing
    Right stud ->
      return $ Just $ ((studentSolution paths), or [ matches
                           normalizeUAST
                           (AST.toUnitype $ normalize stud)
                           (AST.toUnitype (normalize mod))
                         | (Right mod) <- mods ])


