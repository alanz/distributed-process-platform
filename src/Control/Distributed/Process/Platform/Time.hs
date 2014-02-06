{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE TemplateHaskell     #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Distributed.Process.Platform.Time
-- Copyright   :  (c) Tim Watson, Jeff Epstein
-- License     :  BSD3 (see the file LICENSE)
--
-- Maintainer  :  Tim Watson
-- Stability   :  experimental
-- Portability :  non-portable (requires concurrency)
--
-- This module provides facilities for working with time delays and timeouts.
-- The type 'Timeout' and the 'timeout' family of functions provide mechanisms
-- for working with @threadDelay@-like behaviour operates on microsecond values.
--
-- The 'TimeInterval' and 'TimeUnit' related functions provide an abstraction
-- for working with various time intervals and the 'Delay' type provides a
-- corrolary to 'timeout' that works with these.
-----------------------------------------------------------------------------

module Control.Distributed.Process.Platform.Time
  ( -- time interval handling
    microSeconds
  , milliSeconds
  , seconds
  , minutes
  , hours
  , asTimeout
  , after
  , within
  , timeToMicros
  , TimeInterval
  , TimeUnit(..)
  , Delay(..)

  -- timeouts
  , Timeout
  , TimeoutNotification(..)
  , timeout
  , infiniteWait
  , noWait
  ) where

import Control.Concurrent (threadDelay)
import Control.DeepSeq (NFData)
import Control.Distributed.Process
import Control.Distributed.Process.Platform.Internal.Types
import Control.Monad (void)
import Data.Binary
import Data.Typeable (Typeable)

import GHC.Generics

--------------------------------------------------------------------------------
-- API                                                                        --
--------------------------------------------------------------------------------

-- | Defines the time unit for a Timeout value
data TimeUnit = Days | Hours | Minutes | Seconds | Millis | Micros
    deriving (Typeable, Generic, Eq, Show)

instance Binary TimeUnit where
instance NFData TimeUnit where

data TimeInterval = TimeInterval TimeUnit Int
    deriving (Typeable, Generic, Eq, Show)

instance Binary TimeInterval where
instance NFData TimeInterval where

data Delay = Delay TimeInterval | Infinity
    deriving (Typeable, Generic, Eq, Show)  -- TODO: ord/cmp

instance Binary Delay where
instance NFData Delay where

-- | Represents a /timeout/ in terms of microseconds, where 'Nothing' stands for
-- infinity and @Just 0@, no-delay.
type Timeout = Maybe Int

-- | Send to a process when a timeout expires.
data TimeoutNotification = TimeoutNotification Tag
       deriving (Typeable)

instance Binary TimeoutNotification where
  get = fmap TimeoutNotification $ get
  put (TimeoutNotification n) = put n

-- time interval/unit handling (milliseconds)

-- | converts the supplied @TimeInterval@ to milliseconds
asTimeout :: TimeInterval -> Int
asTimeout (TimeInterval u v) = timeToMicros u v

-- | Convenience for making timeouts; e.g.,
--
-- > receiveTimeout (after 3 Seconds) [ match (\"ok" -> return ()) ]
--
after :: Int -> TimeUnit -> Int
after n m = timeToMicros m n

-- | Convenience for making 'TimeInterval'; e.g.,
--
-- > let ti = within 5 Seconds in .....
--
within :: Int -> TimeUnit -> TimeInterval
within n m = TimeInterval m n

microSeconds :: Int -> TimeInterval
microSeconds = TimeInterval Micros

-- | given a number, produces a @TimeInterval@ of milliseconds
milliSeconds :: Int -> TimeInterval
milliSeconds = TimeInterval Millis

-- | given a number, produces a @TimeInterval@ of seconds
seconds :: Int -> TimeInterval
seconds = TimeInterval Seconds

-- | given a number, produces a @TimeInterval@ of minutes
minutes :: Int -> TimeInterval
minutes = TimeInterval Minutes

-- | given a number, produces a @TimeInterval@ of hours
hours :: Int -> TimeInterval
hours = TimeInterval Hours

-- TODO: is timeToMicros efficient enough?

-- | converts the supplied @TimeUnit@ to microseconds
{-# INLINE timeToMicros #-}
timeToMicros :: TimeUnit -> Int -> Int
timeToMicros Micros  us   = us
timeToMicros Millis  ms   = ms  * (10 ^ (3 :: Int)) -- (1000�s == 1ms)
timeToMicros Seconds secs = timeToMicros Millis  (secs * milliSecondsPerSecond)
timeToMicros Minutes mins = timeToMicros Seconds (mins * secondsPerMinute)
timeToMicros Hours   hrs  = timeToMicros Minutes (hrs  * minutesPerHour)
timeToMicros Days    days = timeToMicros Hours   (days * hoursPerDay)

{-# INLINE hoursPerDay #-}
hoursPerDay :: Int
hoursPerDay = 60

{-# INLINE minutesPerHour #-}
minutesPerHour :: Int
minutesPerHour = 60

{-# INLINE secondsPerMinute #-}
secondsPerMinute :: Int
secondsPerMinute = 60

{-# INLINE milliSecondsPerSecond #-}
milliSecondsPerSecond :: Int
milliSecondsPerSecond = 1000

-- timeouts/delays (microseconds)

-- | Constructs an inifinite 'Timeout'.
infiniteWait :: Timeout
infiniteWait = Nothing

-- | Constructs a no-wait 'Timeout'
noWait :: Timeout
noWait = Just 0

-- | Sends the calling process @TimeoutNotification tag@ after @time@ microseconds
timeout :: Int -> Tag -> ProcessId -> Process ()
timeout time tag p =
  void $ spawnLocal $
               do liftIO $ threadDelay time
                  send p (TimeoutNotification tag)
