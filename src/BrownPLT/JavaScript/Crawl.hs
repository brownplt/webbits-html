-- |Crawls an HTML page for JavaScript
module BrownPLT.JavaScript.Crawl 
  ( getPageJavaScript
  ) where

import Control.Monad
import Data.List
import Data.Char (toLower)
import Data.Generics
import System.IO
import Text.ParserCombinators.Parsec.Pos (SourcePos, sourceName)
import Text.ParserCombinators.Parsec(parse,setPosition,incSourceColumn,Column,sourceLine,sourceColumn)

import BrownPLT.Html.Syntax
import qualified BrownPLT.JavaScript as Js
import BrownPLT.JavaScript.HtmlEmbedding


instance Typeable SourcePos where
  typeOf _  = 
    mkTyConApp (mkTyCon "Text.ParserCombinators.Parsec.Pos.SourcePos") []

 
-- Complete guesswork.  It seems to work.
-- This definition is incomplete.
instance Data SourcePos where
  -- We treat source locations as opaque.  After all, we don't have access to
  -- the constructor.
  gfoldl k z pos = z pos
  toConstr _ = sourcePosConstr1 where
    sourcePosConstr1 = mkConstr sourcePosDatatype "SourcePos" [] Prefix
    sourcePosDatatype = mkDataType "SourcePos" [sourcePosConstr1]
  gunfold   = error "gunfold is not defined for SourcePos"
  dataTypeOf = error "dataTypeOf is not defined for SourcePos"


-- |Returns the source of the script.
scriptSrc:: ParsedJsHtml -> [String]
scriptSrc (Element tag attrs _ _) | (map toLower tag) == "script" =
  case attributeValue "src" attrs of -- TODO: Check for type="javascript"?
    Just ""  -> []
    Just url -> [url]
    Nothing  -> []
scriptSrc _ =
  []


-- |Returns a list of URIs for external Javascript files referenced in the page.
importedScripts:: ParsedJsHtml -> [String]
importedScripts = everything (++) (mkQ [] scriptSrc)

-- |Returns the top-level statements of a script.
scriptText :: ParsedJsHtml -> [ParsedStatement]
scriptText (Script (Js.Script _ stmts) _) = stmts
scriptText _ = []

eventHandlers :: [String]
eventHandlers = ["onload","onclick"]; 
-- ,"onmousemove","onmouseover","onmousedown","onmouseout","onmouseup","onselectstart", "onkeypress"]

attrScript :: Attribute SourcePos ParsedJavaScript 
           -> IO [ParsedStatement]
attrScript (Attribute id val loc) | id `elem` eventHandlers = do
  let eventId = drop 2 id -- drop the "on" prefix
  let scriptText = if "javascript:" `isPrefixOf` val then drop 11 val else val
  let eventListenerPrefix = "addEventListener('" ++ eventId ++ "', function(event) { "
  let prefixLen = length eventListenerPrefix
  let eventListenerText = eventListenerPrefix ++ scriptText ++ " });"
  let parser = do
        setPosition (incSourceColumn loc (-prefixLen))
        Js.parseExpression
  case parse parser (sourceName loc) eventListenerText of
    Left err -> do
      fail $ "Error parsiing JavaScript in an attribute at " ++ show loc ++
             "\nThe script was:\n\n" ++ eventListenerText
    Right e -> return [Js.ExprStmt loc e]
attrScript _ = return []

inpageAttrScripts :: ParsedJsHtml -> IO [ParsedStatement]
inpageAttrScripts = everything (liftM2 (++)) (mkQ (return []) attrScript)

inpageScripts :: ParsedJsHtml -> [ParsedStatement]
inpageScripts = everything (++) (mkQ [] scriptText)

parseJsFile path = do
  text <- readFile path
  case Js.parseScriptFromString path text of
    Left err -> fail (show err)
    Right js -> hPutStrLn stderr ("Read file " ++ path) >> return js

-- |Given an HTML page, crawls all external Javascript files and returns a list
-- of statements, concatenated from all files.
getPageJavascript:: ParsedJsHtml -> IO [ParsedStatement]
getPageJavascript page = do
  let importURIs = importedScripts page
  let inpageJs   = inpageScripts page
  attrScripts <- inpageAttrScripts page
  importedScripts <- mapM parseJsFile importURIs
  let unScript (Js.Script _ ss) = ss
  return $ (concatMap unScript importedScripts ++ attrScripts) ++ inpageJs

getPageJavaScript:: ParsedJsHtml -> IO [ParsedStatement] -- monomorphism
getPageJavaScript = getPageJavascript
