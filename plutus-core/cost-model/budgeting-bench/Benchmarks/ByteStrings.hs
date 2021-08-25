module Benchmarks.ByteStrings (makeBenchmarks) where

import           Benchmarks.Common

import           PlutusCore            as PLC

import           Criterion.Main
import qualified Data.ByteString       as BS
import           Data.Functor          ((<&>))
import           System.Random         (StdGen, randomR)

import qualified Hedgehog              as H
import qualified Hedgehog.Internal.Gen as G
import qualified Hedgehog.Range        as R

---------------- ByteString builtins ----------------

integerLength :: BS.ByteString -> Integer
integerLength = fromIntegral . BS.length

byteStringSizes :: [Integer]
byteStringSizes = integerPower 2 <$> [1..20::Integer]

-- Create a bytestring whose memory usage is n.  Since we measure memory usage
-- in 64-bit words we have to create a bytestring containing 8*n bytes.
makeSizedByteString :: H.Seed -> Int -> BS.ByteString
makeSizedByteString seed n = genSample seed (G.bytes (R.singleton (8*n)))

byteStringsToBench :: H.Seed -> [BS.ByteString]
byteStringsToBench seed = (makeSizedByteString seed . fromInteger) <$> byteStringSizes

seedA :: H.Seed
seedA = H.Seed 42 43

seedB :: H.Seed
seedB = H.Seed 44 45

benchTwoByteStrings :: DefaultFun -> Benchmark
benchTwoByteStrings name = createTwoTermBuiltinBench name (byteStringsToBench seedA) (byteStringsToBench seedB)

benchByteStringNoArgOperations :: DefaultFun -> Benchmark
benchByteStringNoArgOperations name =
    bgroup (show name) $
        byteStringsToBench seedA <&> (\x -> benchDefault (showMemoryUsage x) $ mkApp1 name x)

-- Copy the byteString here, because otherwise it'll be exactly the same, and the equality will short-circuit.
benchSameTwoByteStrings :: DefaultFun -> Benchmark
benchSameTwoByteStrings name = createTwoTermBuiltinBenchElementwise name (byteStringsToBench seedA)
                               (fmap BS.copy $ byteStringsToBench seedA)

benchIndexByteString :: StdGen -> Benchmark
benchIndexByteString gen = createTwoTermBuiltinBenchElementwise IndexByteString bytestrings (randomIndices gen bytestrings)
    where bytestrings = byteStringsToBench seedA
          randomIndices gen1 l =
              case l of
                [] -> []
                b:bs -> let (i,gen2) = randomR (0, (integerLength b)-1) gen1
                        in i:randomIndices gen2 bs

{- This should be constant time, since the underlying operations are just
   returning modified pointers into a C array.  We still want a decent number of
   data points, so we generate bytestrings of length 1000, 2000, ..., 10000 and
   for each of them look at four choices each of index and length. -}
benchSliceByteString :: Benchmark
benchSliceByteString =
    let name = SliceByteString
        quarters n = if n < 4 then [n] else [0, t..(n-t)] where t = n `div` 4
        -- quarters n may contain more than four elements if n < 16, but we
        -- won't encounter that case.  For n<4 then the 'else' branch would give
        -- you an infinite list of zeros.
        byteStrings = makeSizedByteString seedA <$> [1000, 2000..10000]
        mkBMsFor b =
            [bgroup (showMemoryUsage start)
             [bgroup (showMemoryUsage len)
              [benchDefault (showMemoryUsage b) $ mkApp3 name start len b] |
              len <- quarters (blen - start)] |
             start <- quarters blen]
            where blen = integerLength b
    in bgroup (show name) $ concatMap mkBMsFor byteStrings

benchConsByteString :: Benchmark -- TODO the numbers are a bit too big here
benchConsByteString = createTwoTermBuiltinBench ConsByteString numbers (byteStringsToBench seedA)
    where numbers = threeToThePower <$> powersOfTwo

makeBenchmarks :: StdGen -> [Benchmark]
makeBenchmarks gen =  (benchTwoByteStrings <$> [ AppendByteString ])
                   <> [benchConsByteString]
                   <> (benchByteStringNoArgOperations <$> [ LengthOfByteString ])
                   <> [benchIndexByteString gen]
                   <> [benchSliceByteString]
                   <> (benchSameTwoByteStrings <$> [ EqualsByteString, LessThanEqualsByteString, LessThanByteString ])

{- Results for bytestrings of size integerPower 2 <$> [1..20::Integer].  The
   biggest inputs here are of size 1048576, or about 4 megabytes.  That's surely
   too big.  Maybe try [1000, 2000, ..., 100000] oor [100, 200, ..., 10000] for
   one-argument functions and [500, 1000, ..., 10000] for two-argument
   functions.


   AppendByteString : good fit for I(x+y), but underpredicts for reasonably-sized
   inputs

   EqualsByteString LessThanEqualsByteString, LessThanByteString: these all
   agree to within 2%, but the plot bends up towards the right.  You get a
   pretty good linear fit for sizes less than 250000

   ConsByteString: this does appear to be linear in the size of the string, and
   the size of the thing you're consing is irrelevant.  Again, the inputs are a
   bit too big.

   LengthOfByteString: this does appear to be pretty much constant, although
   it's hard to tell over the exponential range of scales we have here.  The
   time taken varies between 888ns and 1143ns, but randomly.  We could do with
   more data points here, and more uniformly spaced.

   IndexByteString: again this looks constant.  More uniform spacing would be
   good.

   SliceByteString: again, pretty constant.

   Overall it looks like we'd get good models with smaller and evenly spaced
   strings. We should do this but check what happens with larger inputs for
   AppendByteString.  We should also give more inputs to the single-argument
   functions.

-}