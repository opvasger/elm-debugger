module DevTools.Browser.Element.Icon exposing
    ( Icon
    , viewCollapse
    , viewExpand
    , viewModel
    )

import Html exposing (Html)
import Svg exposing (path, svg, text, title)
import Svg.Attributes exposing (d, fill, style, viewBox)
import Svg.Events exposing (onClick, onMouseOut, onMouseOver)


type Icon
    = Collapse
    | Expand
    | ViewModel


viewCollapse :
    { onFocus : Maybe Icon -> msg
    , onClick : msg
    , title : String
    , focus : Maybe Icon
    }
    -> Html msg
viewCollapse config =
    svg
        [ style "width:20px;height:20px;cursor:pointer;"
        , viewBox "0 0 24 24"
        , onMouseOver (config.onFocus (Just Collapse))
        , onMouseOut (config.onFocus Nothing)
        , onClick config.onClick
        ]
        [ title [] [ text config.title ]
        , path
            [ if config.focus == Just Collapse then
                fill "black"

              else
                fill "#6e6e6e"
            , d "M19,6.41L17.59,5L12,10.59L6.41,5L5,6.41L10.59,12L5,17.59L6.41,19L12,13.41L17.59,19L19,17.59L13.41,12L19,6.41Z"
            ]
            []
        ]


viewExpand :
    { onFocus : Maybe Icon -> msg
    , onClick : msg
    , title : String
    , focus : Maybe Icon
    }
    -> Html msg
viewExpand config =
    svg
        [ style "width:20px;height:20px;cursor:pointer;"
        , viewBox "0 0 24 24"
        , onMouseOver (config.onFocus (Just Expand))
        , onMouseOut (config.onFocus Nothing)
        , onClick config.onClick
        ]
        [ title [] [ text config.title ]
        , path
            [ if config.focus == Just Expand then
                fill "black"

              else
                fill "#6e6e6e"
            , d "M14,12H10V10H14M14,16H10V14H14M20,8H17.19C16.74,7.22 16.12,6.55 15.37,6.04L17,4.41L15.59,3L13.42,5.17C12.96,5.06 12.5,5 12,5C11.5,5 11.04,5.06 10.59,5.17L8.41,3L7,4.41L8.62,6.04C7.88,6.55 7.26,7.22 6.81,8H4V10H6.09C6.04,10.33 6,10.66 6,11V12H4V14H6V15C6,15.34 6.04,15.67 6.09,16H4V18H6.81C7.85,19.79 9.78,21 12,21C14.22,21 16.15,19.79 17.19,18H20V16H17.91C17.96,15.67 18,15.34 18,15V14H20V12H18V11C18,10.66 17.96,10.33 17.91,10H20V8Z"
            ]
            []
        ]


viewModel :
    { isEnabled : Bool
    , onFocus : Maybe Icon -> msg
    , onClick : msg
    , title : String
    , focus : Maybe Icon
    }
    -> Html msg
viewModel config =
    svg
        [ style "width:20px;height:20px;cursor:pointer;"
        , viewBox "0 0 25 25"
        , onMouseOver (config.onFocus (Just ViewModel))
        , onMouseOut (config.onFocus Nothing)
        , onClick config.onClick
        ]
        [ title [] [ text config.title ]
        , path
            [ if config.isEnabled then
                fill "#60b5cc"

              else if config.focus == Just ViewModel then
                fill "black"

              else
                fill "#6e6e6e"
            , d "M5,3H7V5H5V10A2,2 0 0,1 3,12A2,2 0 0,1 5,14V19H7V21H5C3.93,20.73 3,20.1 3,19V15A2,2 0 0,0 1,13H0V11H1A2,2 0 0,0 3,9V5A2,2 0 0,1 5,3M19,3A2,2 0 0,1 21,5V9A2,2 0 0,0 23,11H24V13H23A2,2 0 0,0 21,15V19A2,2 0 0,1 19,21H17V19H19V14A2,2 0 0,1 21,12A2,2 0 0,1 19,10V5H17V3H19M12,15A1,1 0 0,1 13,16A1,1 0 0,1 12,17A1,1 0 0,1 11,16A1,1 0 0,1 12,15M8,15A1,1 0 0,1 9,16A1,1 0 0,1 8,17A1,1 0 0,1 7,16A1,1 0 0,1 8,15M16,15A1,1 0 0,1 17,16A1,1 0 0,1 16,17A1,1 0 0,1 15,16A1,1 0 0,1 16,15Z"
            ]
            []
        ]