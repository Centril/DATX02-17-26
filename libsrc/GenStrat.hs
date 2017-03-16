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

{-# LANGUAGE LambdaCase, DeriveDataTypeable, DeriveGeneric #-}

module GenStrat where

import Ideas.Common.Library
import Ideas.Common.DerivationTree
import Ideas.Common.Strategy as S
import Ideas.Common.Strategy.Sequence hiding ((.*.))
import Control.Monad.State
import Control.Monad as M
import Data.Generics.Uniplate.DataOnly (transformBi)
import Data.Data (Data, Typeable)
import GHC.Generics (Generic)
import Debug.Trace

import CoreS.ASTUnitype
import CoreS.ASTUnitypeUtils

type Generator = Int -> AST -> State Int (Strategy AST)

nextId :: State Int Int
nextId = do
  i <- get
  modify (+1)
  return i

holeId (Hole i) = Just i
holeId _        = Nothing

refine :: AST -> Int -> Strategy AST
refine ast i = toStrategy $ makeRule ruleId f
   where
      f p = Just $ transformBi refine' p

      refine' e
         | holeId e == Just i = ast
         | otherwise          = e

      ruleId = "refine" ++ show i

-- Creates a DAG of dependencies of given ASTs, in the form of a list where
-- each element describes a node and a list of all other nodes that node are
-- dependant on
dagHelper :: [(AST, Int)] -> [(AST, Int)] -> [((AST, Int), [(AST, Int)])]
dagHelper [] _       = []
dagHelper (a:as) old =
  (a, (filter ((`dependsOn` (fst a)) . fst) old)):(dagHelper as (a:old))

-- Returns all possible topological orderings in a RoseTree, where each level
-- represents a new step, and its elements possible pathways.
allTop :: ((AST, Int), [(AST, Int)])
       -> [((AST, Int), [(AST, Int)])]
       -> RoseTree AST
allTop top [] = RoseTree ((fst . fst) top) []
allTop top as = RoseTree ((fst . fst) top)
                       $ map (\x -> allTop x (rest x as))
                       $ filter ((0 ==) . length . snd) as
  where
    rest ((t,i),ts) rs = map (\(a,b) -> (a, (filter ((/=i) . snd) b)))
                           $ filter ((/=i) . snd . fst) rs

-- Generates a strategy for the possible pathways of a given RoseTree
makeAllTopStrat :: RoseTree AST -> [Int] -> State Int (Strategy AST)
makeAllTopStrat (RoseTree r []) [loc]    = genStrat loc r
makeAllTopStrat (RoseTree r ts) (loc:ls) =
  (.*.) <$> (genStrat loc r)
        <*> foldr (\x -> ((.|.) <$> (makeAllTopStrat x ls) <*>))
                  (return $ failS) ts

-- Generates a strategy handling all possible orderings of AST
makeDependencyStrategy :: [(AST, Int)] -> State Int (Strategy AST)
makeDependencyStrategy = \case
  []         -> return $ succeed
  [(x, loc)] -> genStrat loc x
  as         ->  makeAllTopStrat (allTop ((SEmpty,-1),[]) (dagHelper as []))
                 $ (-1):(map snd as)

-- | Can we make this more DRY?
--
-- (generics?)
genStrat :: Generator
genStrat loc (Block xs)                   = refList loc Block xs
genStrat loc (MethodDecl t i params body) = refList loc (MethodDecl t i params) body
genStrat loc (ClassDecl i body)           = (ClassDecl i $$ body) loc
genStrat loc (ClassBody body)             = refList loc ClassBody body
genStrat loc (ClassTypeDecl body)         = (ClassTypeDecl $$ body) loc
genStrat loc (CompilationUnit body)       = refList loc CompilationUnit body
genStrat loc (MemberDecl body)            = (MemberDecl $$ body) loc
-- Catch all clause for things we have yet to implement
genStrat loc x = return $ refine x loc

refList loc cons xs = do
  ids <- M.sequence [nextId | _ <- xs]
  strategy <- makeDependencyStrategy (zip xs ids)
  return $ refine (cons (map Hole ids)) loc .*. strategy

locGen :: AST -> State Int (Int, Strategy AST)
locGen ast = do
  loc <- nextId
  strat <- genStrat loc ast
  return $ (loc, strat)

($$) :: (AST -> AST) -> AST -> Int -> State Int (Strategy AST)
($$) cons body loc = do
  (bodyLoc, bodyStrat) <- locGen body
  return $ refine (cons (Hole bodyLoc)) loc .*. bodyStrat

makeStrategy :: AST -> Strategy AST
makeStrategy ast = fst $ runState (genStrat 0 ast) 1

data RoseTree a = RoseTree a [RoseTree a]
  deriving (Eq, Ord, Show, Read, Typeable, Data, Generic)

makeASTsRoseTree :: Strategy AST -> RoseTree AST
makeASTsRoseTree strat = tree
  where
    tree = go (Hole 0, (firstsTree (emptyPrefix strat (Hole 0))))

    go :: (AST, DerivationTree (Elem (Prefix AST)) (Prefix AST)) -> RoseTree AST
    go (ast, t) = RoseTree ast (map go (zip (map (get . fst) (firsts (root t))) (subtrees t)))

    get (_, term, _) = term

-- | Simple DFS traversal
matchesDFS :: (AST -> AST) -> RoseTree AST -> AST -> Bool
matchesDFS norm tree ast = go [tree]
  where
    go [] = False
    go ((RoseTree a []):trees)
      | ast == (norm a) = True
      | otherwise       = go trees
    go ((RoseTree a asts):trees)
      | canMatch ast (norm a) = go (asts ++ trees)
      | otherwise             = go trees

-- | Simple BFS traversal
matchesBFS :: (AST -> AST) -> RoseTree AST -> AST -> Bool
matchesBFS norm tree ast = go [tree]
  where
    go [] = False
    go ((RoseTree a []):trees) = ast == (norm a) || go trees
    go ((RoseTree a asts):trees)
      | canMatch ast (norm a) = go (trees ++ asts)
      | otherwise      = go trees

makeASTs :: Strategy AST -> [AST]
makeASTs strat = map lastTerm $ derivationList (\_ _ -> EQ) strat (Hole 0)

-- | `matches a b` checks if `a` matches the strategy generated
-- by `b`
matches :: (AST -> AST) -> AST -> AST -> Bool
matches norm a b = matchesDFS norm (makeASTsRoseTree (makeStrategy b)) a