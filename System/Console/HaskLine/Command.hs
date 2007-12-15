module System.Console.HaskLine.Command where

import System.Console.HaskLine.LineState
import System.Console.Terminfo
import Data.Maybe

import qualified Data.Map as Map
import Data.Maybe (catMaybes)
import System.Console.Terminfo
import System.Posix (Fd,stdOutput)
import System.Posix.Terminal

data Key = KeyChar Char | KeySpecial SKey
                deriving (Show,Eq,Ord)
data SKey = KeyLeft | KeyRight | KeyUp | KeyDown
            | Backspace | DeleteForward | KillLine
                deriving (Eq,Ord,Enum,Show)

getKeySequences :: Terminal -> IO (Map.Map String SKey)
getKeySequences term = do
    sttys <- sttyKeys
    return $ Map.union sttys (terminfoKeys term)

terminfoKeys :: Terminal -> Map.Map String SKey
terminfoKeys term = Map.fromList $ catMaybes 
                    $ map getSequence keyCapabilities
        where getSequence (cap,x) = getCapability term $ do 
                            keys <- cap
                            return (keys,x)

keyCapabilities = [(keyLeft,KeyLeft),
                (keyRight,KeyRight),
                (keyUp,KeyUp),
                (keyDown,KeyDown),
                (keyBackspace,Backspace),
                (keyDeleteChar,DeleteForward)]

sttyKeys :: IO (Map.Map String SKey)
sttyKeys = do
    attrs <- getTerminalAttributes stdOutput
    let getStty (k,c) = do {str <- controlChar attrs k; return ([str],c)}
    return $ Map.fromList $ catMaybes
            $ map getStty [(Erase,Backspace),(Kill,KillLine)]

getKey :: [(String, SKey)] -> IO Key
getKey ms = do 
    c <- getChar
    case mapMaybe (matchHead c) ms of
        [] -> return (KeyChar c)
        [("",k)] -> return (KeySpecial k)
        ms' -> getKey ms'
  where
    matchHead c (d:ds,k)  | c == d = Just (ds,k)
    matchHead _ _                  = Nothing


        
{-- todo: some commands only change the linestate, don't require
 a full refresh:
 data Command m = Change (LSCHANGE) | Refresh (Linestate -> m LineState)
 --}
data Command m = Finish | ChangeCmd (LineState -> m LineState)

isFinish :: Command m -> Bool
isFinish Finish = True
isFinish _ = False

type Commands m = Map.Map Key (Command m)

simpleCommands :: Monad m => Commands m
simpleCommands = Map.fromList $ [
                    (KeyChar '\n', Finish)
                    ,(KeySpecial KeyLeft, pureCommand goLeft)
                    ,(KeySpecial KeyRight, pureCommand goRight)
                    ,(KeySpecial Backspace, pureCommand deletePrev)
                    ,(KeySpecial DeleteForward, pureCommand deleteNext)
                    ,(KeySpecial KillLine, pureCommand killLine)
                    ] ++ map insertionCommand [' '..'~']
            
pureCommand :: Monad m => LineChange -> Command m
pureCommand f = ChangeCmd (return . f)

insertionCommand :: Monad m => Char -> (Key,Command m)
insertionCommand c = (KeyChar c, pureCommand $ insertChar c)

                    