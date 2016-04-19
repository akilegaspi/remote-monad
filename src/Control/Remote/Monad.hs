{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module:      Control.Remote.Monad.Packet.Weak
Copyright:   (C) 2016, The University of Kansas
License:     BSD-style (see the file LICENSE)
Maintainer:  Andy Gill
Stability:   Alpha
Portability: GHC
-}

module Control.Remote.Monad 
  ( -- * The remote monad
    RemoteLocalMonad
  , RemoteMonad
  , RemoteMonadException(..)
    -- * The primitive lift functions
  , command
  , procedure
  , local
  , loop
    -- * The run functions
  , RunMonad(runLocalMonad)
  , runMonad
  , runWeakMonad
  , runStrongMonad
  , runApplicativeMonad
  ) where

import Control.Monad.Trans.Class
import Control.Monad.Trans.State.Strict

import qualified Control.Remote.Applicative as A
import           Control.Remote.Monad.Packet.Applicative as A
import           Control.Remote.Monad.Packet.Weak as Weak
import           Control.Remote.Monad.Packet.Strong as Strong
import           Control.Remote.Monad.Types as T
import           Control.Applicative

import Control.Natural
import Control.Monad.Catch
import Control.Monad.Trans.Maybe
import Control.Monad.Identity
import Control.Category ((>>>))

type RemoteMonad = RemoteLocalMonad Identity 

-- | promote a command into the remote monad
command :: c -> RemoteLocalMonad l c p ()
command = Appl . A.command

-- | promote a procedure into the remote monad
procedure :: p a -> RemoteLocalMonad l c p a
procedure = Appl . A.procedure 

local :: l a -> RemoteLocalMonad l c p a
local = Appl . A.local

loop :: forall a c p l . (a-> Bool) -> RemoteLocalMonad l c p a -> RemoteLocalMonad l c p a
loop f m = do  res <- m
               if f res then
                 loop f m
                else
                  return res 

-- | 'RunMonad' is the overloading for choosing the appropriate bundling strategy for a monad.
class RunMonad f where
  -- | This overloaded function chooses the appropriate bundling strategy
  --   based on the type of the handler your provide.
  runLocalMonad :: (MonadCatch m) => (l :~> m)->(f c p :~> m) -> (RemoteLocalMonad l c p :~> m)

instance RunMonad WeakPacket where
  runLocalMonad = runWeakMonad
  
instance RunMonad StrongPacket where
  runLocalMonad = runStrongMonad

instance RunMonad ApplicativePacket where
  runLocalMonad = runApplicativeMonad

runMonad  :: (RunMonad f, MonadCatch m) => (f c p :~> m) -> (RemoteMonad c p :~> m)
runMonad = runLocalMonad $ nat (return . runIdentity)   



-- | This is a remote monad combinator, that takes an implementation
--   of a remote applicative, splits the monad into applicatives
--   without any merge stragegy, and uses the remote applicative.
--   Every '>>=' will generate a call to the 'RemoteApplicative'
--   handler; as well as one terminating call.
--   Using 'runBindeeMonad' with a 'runWeakApplicative' gives the weakest remote monad.
runMonadSkeleton :: (MonadCatch m) => ( RemoteLocalApplicative l c p :~> m) -> (RemoteLocalMonad l c p :~> m)
runMonadSkeleton f = nat $ \ case 
  Appl g   -> run f g
  Bind g k -> (runMonadSkeleton f # g) >>= \ a -> runMonadSkeleton f # (k a)
  Ap' g h  -> (runMonadSkeleton f # g) <*> (runMonadSkeleton f # h)
  Alt m1 m2 -> (runMonadSkeleton f # m1) 
                  `catch`(\ e-> case e :: RemoteMonadException of
                            RemoteEmptyException -> runMonadSkeleton f # m2
                            _                    -> throwM e
                         )
  Empty     -> throwM RemoteEmptyException
  Throw e   -> throwM e 
  Catch m h -> catch (runMonadSkeleton f # m)  ((runMonadSkeleton f #) . h)

-- | This is the classic weak remote monad, or technically the
--   weak remote applicative weak remote monad.
runWeakMonad :: (MonadCatch m) => (l :~> m) -> (WeakPacket c p :~> m) -> (RemoteLocalMonad l c p :~> m)
runWeakMonad lf  = runMonadSkeleton . A.runWeakApplicative lf

-- | This is the classic strong remote monad. It bundles
--   packets (of type 'StrongPacket') as large as possible,
--   including over some monadic binds.
runStrongMonad :: forall m c p l . (MonadCatch m) => (l :~> m) -> (StrongPacket c p :~> m) -> (RemoteLocalMonad l c p :~> m)
runStrongMonad (Nat lf) (Nat rf) = nat $ \ p -> do
    (r,HStrongPacket h) <- runStateT (runMaybeT (go2 p)) (HStrongPacket id)
    rf $ h $ Strong.Done
    case r of 
       Nothing -> throwM RemoteEmptyException
       Just v  -> return v 
  where
    go2 :: forall a . RemoteLocalMonad l c p a -> MaybeT (StateT (HStrongPacket c p) m) a
    go2 (Appl app)   = lift $ go app
    go2 (Bind app k) = go2 app >>= \ a -> go2 (k a)
    go2 (Ap' g h)    = go2 g <*> go2 h
    go2 (Alt m1 m2)  = go2 m1  <|> go2 m2
    go2 Empty        = empty
    go2 (Throw e)    = lift $ do 
        HStrongPacket cs <-  get
        put (HStrongPacket id) 
        () <- lift $ rf $ cs Strong.Done
        throwM e 
    go2 (Catch m h) = catch (go2 m) (go2 . h)

    go :: forall a . T.RemoteLocalApplicative l c p a -> StateT (HStrongPacket c p) m a
    go (T.Pure a)      = return a
    go (T.Command c)   = do
        modify (\ (HStrongPacket cs) -> HStrongPacket (cs . Strong.Command c))
        return ()
    go (T.Procedure p) = do
        HStrongPacket cs <- get
        put (HStrongPacket id)
        r2 <- lift $ rf $ cs $ Strong.Procedure $ p
        return $ r2
    go (T.Ap g h) = go g <*> go h
    go (T.Local m) = lift $ lf m
    
-- | The is the strong applicative strong remote monad. It bundles
--   packets (of type 'RemoteApplicative') as large as possible, 
--   including over some monadic binds.
runApplicativeMonad :: forall m c p l . (MonadCatch m) => (l :~> m) -> (A.ApplicativePacket c p :~> m) -> (RemoteLocalMonad l c p :~> m)
runApplicativeMonad (Nat lf) (Nat rf) = nat $ \ p -> do
    (r,h) <-  runStateT (runMaybeT (go2 p)) (pure ()) 
    rf $ pk $ h -- should we stub out the call with only 'Pure'?
    case r of
      Nothing -> throwM RemoteEmptyException
      Just v -> return v
  where
    go2 :: forall a . RemoteLocalMonad l c p a -> MaybeT (StateT (T.RemoteLocalApplicative l c p ()) m) a
    go2 (Appl app)   = lift $ go app
    go2 (Bind app k) = go2 app >>= \ a -> go2 (k a)
    go2 (Ap' g h)    = go2 g <*> go2 h
    go2 (Alt m1 m2)  = go2 m1 <|> go2 m2
    go2 Empty        = empty
    go2 (Throw e)    = lift $ do
        ap' <- get
        put (pure ())
        ()<-lift $ rf $ (pk ap')
        throwM e
    go2 (Catch m h) = catch (go2 m) (go2 . h)

         

    go :: forall a .  T.RemoteLocalApplicative l c p a -> StateT (T.RemoteLocalApplicative l c p ()) m a
    go ap = case superApplicative ap of
                Nothing -> do
                  case ap of 
                    (T.Local m)-> lift $ lf m
                    otherwise -> do
                                ap' <- get
                                put (pure ())
                                lift $ rf $ (pk (ap' *> ap))
                Just a -> do
                  modify (\ ap' -> ap' <* ap)
                  return a

    superApplicative :: T.RemoteLocalApplicative l c p a -> Maybe a
    superApplicative (T.Pure a)      = pure a
    superApplicative (T.Command   c) = Just ()
    superApplicative (T.Procedure p) = Nothing
    superApplicative (T.Local m)     = Nothing 
    superApplicative (T.Ap g h)      = superApplicative g <*> superApplicative h


    -- It all comes down to this. Converting quickly between T.RemoteApplicative and ApplicativePacket.
    
    pk :: T.RemoteLocalApplicative l c p a -> ApplicativePacket c p a
    pk (T.Pure a)      = A.Pure a
    pk (T.Command   c) = A.Command c
    pk (T.Procedure p) = A.Procedure p
    pk (T.Ap g h)      = A.Zip ($) (pk g) (pk h)
