module Benchmarks.Misc (makeBenchmarks) where

import           Benchmarks.Common

import           Criterion.Main
import           System.Random     (StdGen)

makeBenchmarks :: StdGen -> [Benchmark]
makeBenchmarks _gen = []

{- TODO
   mkPairData
   mkNilData
   mkNilPairData
-}