{-# LANGUAGE FlexibleContexts         #-}

module Language.Haskell.Liquid.Bare.Env (
    BareM
  , Warn
  , TCEnv

  , BareEnv(..)

  -- , TInline(..)
  , InlnEnv

  , inModule
  , withVArgs

  , setRTAlias
  , setREAlias
  , setEmbeds

  , execBare

  , insertLogicEnv
  , insertAxiom
  , addDefs
  ) where

import           HscTypes
import           Prelude                              hiding (error)
import           Text.Parsec.Pos
import           TyCon
import           Var

import           Control.Monad.Except
import           Control.Monad.State
import           Control.Monad.Writer

import qualified Control.Exception                    as Ex
import qualified Data.HashMap.Strict                  as M
import qualified Data.HashSet                         as S


import           Language.Fixpoint.Types              (Expr(..), Symbol, symbol, TCEmb)

import           Language.Haskell.Liquid.UX.Errors    ()
import           Language.Haskell.Liquid.Types
import           Language.Haskell.Liquid.Types.Bounds


--------------------------------------------------------------------------------
-- | Error-Reader-IO For Bare Transformation -----------------------------------
--------------------------------------------------------------------------------

-- FIXME: don't use WriterT [], very slow
type BareM = WriterT [Warn] (ExceptT Error (StateT BareEnv IO))

type Warn  = String

type TCEnv = M.HashMap TyCon RTyCon

type InlnEnv = M.HashMap Symbol LMap

data BareEnv = BE
  { modName  :: !ModName
  , tcEnv    :: !TCEnv
  , rtEnv    :: !RTEnv
  , varEnv   :: M.HashMap Symbol Var -- S.HashSet (Symbol, Var) -- [(Symbol, Var)]
  , hscEnv   :: HscEnv
  , logicEnv :: LogicMap
  , bounds   :: RBEnv
  , embeds   :: TCEmb TyCon
  , axSyms   :: M.HashMap Symbol LocSymbol
  }

setEmbeds :: TCEmb TyCon -> BareM ()
setEmbeds emb = modify $ \be -> be {embeds = emb}


insertLogicEnv :: String -> LocSymbol -> [Symbol] -> Expr -> BareM ()
insertLogicEnv _msg x ys e = modify $ \be -> be {logicEnv = (logicEnv be) {lmSymDefs = M.insert (val x) (LMap x ys e) $ lmSymDefs $ logicEnv be}}

insertAxiom :: Var -> Maybe Symbol -> BareM ()
insertAxiom x s
  = modify $ \be -> be {logicEnv = (logicEnv be) {lmVarSyms = M.insert x s $ lmVarSyms $ logicEnv be}}

addDefs :: S.HashSet (Var, Symbol) -> BareM ()
addDefs ds
  = forM_ (S.toList ds) $ \(v, x) -> insertAxiom v (Just x)

setModule :: ModName -> BareEnv -> BareEnv
setModule m b = b { modName = m }

inModule :: ModName -> BareM b -> BareM b
inModule m act = do
  old <- gets modName
  modify $ setModule m
  res <- act
  modify $ setModule old
  return res

withVArgs :: (Foldable t, PPrint a)
          => SourcePos
          -> SourcePos
          -> t a
          -> BareM b
          -> BareM b
withVArgs l l' vs act = do
  old <- gets rtEnv
  mapM_ (mkExprAlias l l' . symbol . showpp) vs
  res <- act
  modify $ \be -> be { rtEnv = old }
  return res

mkExprAlias :: SourcePos -> SourcePos -> Symbol -> BareM ()
mkExprAlias l l' v = setRTAlias v (RTA v [] [] (RExprArg (Loc l l' $ EVar $ symbol v)) l l')

setRTAlias :: Symbol -> RTAlias RTyVar SpecType -> BareM ()
setRTAlias s a = modify $ \b -> b { rtEnv = mapRT (M.insert s a) $ rtEnv b }

setREAlias :: Symbol -> RTAlias Symbol Expr -> BareM ()
setREAlias s a = modify $ \b -> b { rtEnv = mapRE (M.insert s a) $ rtEnv b }

------------------------------------------------------------------
execBare :: BareM a -> BareEnv -> IO (Either Error a)
------------------------------------------------------------------
execBare act benv =
   do z <- evalStateT (runExceptT (runWriterT act)) benv `Ex.catch` (return . Left)
      case z of
        Left s        -> return $ Left s
        Right (x, ws) -> do forM_ ws $ putStrLn . ("WARNING: " ++)
                            return $ Right x
