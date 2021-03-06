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

{-# LANGUAGE LambdaCase #-}

-- | Normalizers for simplifying if + else statements
-- where some branch is empty.
module Norm.IfElseEmpty (
  -- * Normalizers
    normIESiEmpty
  , normIESeEmpty
  , normIEBothEmpty
  ) where

import Util.Monad (traverseJ)

import Norm.NormCS

-- TODO allocate stages. At the moment chosen arbitrarily.
stage :: Int
stage = 1

--------------------------------------------------------------------------------
-- Exported Rules:
--------------------------------------------------------------------------------

-- | Simplifies an if else where the if branch is empty.
-- > if ( c ) ; else se => if ( !c ) se
-- and:
-- > if ( c ) ; => sideEffectsOf( c )
normIESiEmpty :: NormCUR
normIESiEmpty = makeRule' "if_else_empty.stmt.si_empty" [stage] execIESiEmpty

-- | Simplifies an if else where the else branch is empty.
-- > if ( c ) si else ; => if ( c ) si
normIESeEmpty :: NormCUR
normIESeEmpty = makeRule' "if_else_empty.stmt.se_empty" [stage] execIESeEmpty

-- | Simplifies an if else where both branches are empty.
-- > if ( c ) ; else ; => sideEffectsOf( c )
normIEBothEmpty :: NormCUR
normIEBothEmpty = makeRule' "if_else_empty.stmt.both_empty" [stage]
                            execIEBothEmpty

--------------------------------------------------------------------------------
-- if_else_empty.stmt.si_empty:
--------------------------------------------------------------------------------

execIESiEmpty :: NormCUA
execIESiEmpty = normEvery $ traverseJ $ \case
  SIf     c SEmpty    -> change $ exprIntoStmts c
  SIfElse c SEmpty se -> change [SIf (ENot c) se]
  x -> unique [x]

--------------------------------------------------------------------------------
-- if_else_empty.stmt.se_empty:
--------------------------------------------------------------------------------

execIESeEmpty :: NormCUA
execIESeEmpty = normEvery $ \case
  SIfElse c si SEmpty -> change $ SIf c si
  x -> unique x

--------------------------------------------------------------------------------
-- if_else_empty.stmt.both_empty:
--------------------------------------------------------------------------------

execIEBothEmpty :: NormCUA
execIEBothEmpty = normEvery $ traverseJ $ \case
  SIfElse c SEmpty SEmpty -> change $ exprIntoStmts c
  x -> unique [x]