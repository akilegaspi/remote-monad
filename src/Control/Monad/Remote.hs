{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module:      Control.Monad.Remote.Packet.Weak
Copyright:   (C) 2016, The University of Kansas
License:     BSD-style (see the file LICENSE)
Maintainer:  Andy Gill
Stability:   Alpha
Portability: GHC
-}

module Control.Monad.Remote where

import Control.Monad.Remote.Packet.Applicative as Packet
import Control.Monad.Remote.Packet.Weak as Weak
import Control.Monad.Remote.Packet.Strong as Strong

import Control.Natural

data Remote c p a where
   Appl        :: Packet.Packet c p a -> Remote c p a
   Bind        :: Packet.Packet c p a -> (a -> Remote c p b) -> Remote c p b
  
instance Functor (Remote c p) where
  fmap f m = pure f <*> m

instance Applicative (Remote c p) where
  pure a                = Appl (pure a)
  Appl f   <*> Appl g   = Appl (f <*> g)
  Appl f   <*> Bind m k = Bind (pure (,) <*> f <*> m) (\ (a,b) -> fmap a $ k b)
  Bind m k <*> r        = Bind m (\ a -> k a <*> r)

instance Monad (Remote c p) where
  return = pure
  Bind m k >>= k2 = Bind m (\ a -> k a >>= k2)

command :: c -> Remote c p ()
command = Appl . Packet.Command (pure ())

procedure :: p a -> Remote c p a
procedure = Appl . Packet.Procedure (pure id)

runWeak :: forall m c p a f . (Weak.WeakSend f, Monad m) => (f c p ~> m) -> (Remote c p ~> m)
runWeak f (Appl g)   = Packet.toPacket (Strong.toPacket f) g
runWeak f (Bind g k) = Packet.toPacket (Strong.toPacket f) g >>= runWeak f . k

runStrong :: forall m c p a f . (Strong.StrongSend f, Monad m) => (f c p ~> m) -> (Remote c p ~> m)
runStrong = undefined

--runStrongApplicative :: forall m c p a f . (Applicative.ApplicativeSend f, Monad m) => (f c p ~> m) -> (Remote c p ~> m)
--runStrongApplicative = undefined
