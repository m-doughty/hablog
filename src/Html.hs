{-# LANGUAGE OverloadedStrings #-}

module Html where

import Data.Foldable (foldMap)
import Data.Monoid (mconcat)
import Data.String (fromString)
import qualified Data.Text.Lazy as T
import qualified Text.Blaze.Html5 as H
import Text.Blaze.Html5 ((!))
import qualified Text.Blaze.Html5.Attributes as A

import Model

template :: T.Text -> H.Html -> H.Html
template title container =
  H.docTypeHtml $ do
    H.head $ do
      H.title (H.toHtml title)
      H.link ! A.rel "stylesheet" ! A.type_ "text/css" ! A.href "/static/css/style.css"
    H.body $ do
      H.div ! A.class_ "container" $ do
        logo
        H.div ! A.class_ "maincontainer" $ container


mainTemplate :: H.Html -> H.Html
mainTemplate content = do
        --mainNav
        H.article ! A.class_ "content" $ content

notFoundPage :: H.Html
notFoundPage =
  template "Not Found" $ mainTemplate $ do
    H.h1 "Not found"
    H.p "The page you search for is not available."

logo :: H.Html
logo = H.header ! A.class_ "logo" $ H.h1 $ H.a ! A.href "/" $ "Hablog"

errorPage :: String -> H.Html
errorPage msg =
  template "Error" $ do
    H.h2 $ "Something Went Wrong..."
    H.p $ H.toHtml msg

emptyPage :: H.Html
emptyPage = H.span " "

postsList :: [Post] -> H.Html
postsList = H.ul . mconcat . fmap postsListItem

postsListItem :: Post -> H.Html
postsListItem post = do
  H.li $ H.a ! A.href (fromString (show post)) $ H.toHtml $ title post