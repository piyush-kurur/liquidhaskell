
{-# LANGUAGE QuasiQuotes #-}

module ElimExList (prop) where

import LiquidHaskell
import Prelude hiding (head)

--------------------------------------------------------------------------
[lq| prop :: a -> MyEven |]
prop _ = (head ys) - 1
  where 
    ys = Cons 1 (Cons 3 (Cons 5 Nil))
--------------------------------------------------------------------------

[lq| type MyEven = {v:Int | v mod 2 == 0 } |]

data List a = Nil | Cons a (List a)

head :: List a -> a 
head (Cons x _) = x

