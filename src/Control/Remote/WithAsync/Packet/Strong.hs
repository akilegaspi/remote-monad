{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module:      Control.Remote.WithAsync.Monad.Packet.Strong
Copyright:   (C) 2016, The University of Kansas
License:     BSD-style (see the file LICENSE)
Maintainer:  Andy Gill
Stability:   Alpha
Portability: GHC
-}

module Control.Remote.WithAsync.Packet.Strong where

import qualified Control.Remote.WithAsync.Packet.Weak as Weak
import           Control.Remote.WithAsync.Packet.Weak (WeakPacket)
import           Control.Natural


-- | A Strong Packet, that can encode a list of commands, terminated by an optional procedure.

data StrongPacket (c :: *) (p :: * -> *) (a :: *) where
   Command   :: c -> StrongPacket c p b -> StrongPacket c p b
   Procedure :: p a                     -> StrongPacket c p a
   Done      ::                            StrongPacket c p ()

-- | A Hughes-style version of 'StrongPacket', with efficent append.
newtype HStrongPacket c p = HStrongPacket (StrongPacket c p ~> StrongPacket c p)