module DevTools.Browser.Program exposing
    ( Model
    , Msg
    , Program
    , mapDocument
    , mapHtml
    , mapInit
    , mapSubscriptions
    , mapUpdate
    , mapUrlMsg
    )

import Browser
import File exposing (File)
import File.Download
import File.Select
import History exposing (History)
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Task exposing (Task)
import Throttle exposing (Throttle)


type alias Program flags model msg =
    Platform.Program flags (Model model msg) (Msg model msg)


type Msg model msg
    = DoNothing
    | UpdateApp MsgSrc msg
    | ResetApp
    | ReplayApp Int
    | ToggleAppReplay
    | ToggleViewInteractive
    | ToggleDecodeStrategy
    | ToggleModelVisibility
    | DownloadSession
    | SelectSession
    | DecodeSession File
    | SessionDecoded (Result Decode.Error (Model model msg))
    | InputDescription String
    | UpdateCacheThrottle Throttle.Tick


type alias Model model msg =
    { history : History model msg
    , initCmd : Cmd msg
    , isViewInteractive : Bool
    , isModelVisible : Bool
    , decodeStrategy : DecodeStrategy
    , decodeError : Maybe ( SessionSrc, Decode.Error )
    , description : String
    , cacheThrottle : Throttle
    }


mapUrlMsg : msg -> Msg model msg
mapUrlMsg =
    UpdateApp Url


mapInit :
    { init : ( model, Cmd msg )
    , msgDecoder : Decoder msg
    , update : msg -> model -> ( model, Cmd msg )
    , fromCache : Maybe String
    }
    -> ( Model model msg, Cmd (Msg model msg) )
mapInit config =
    let
        decodeSession =
            config.init
                |> sessionDecoder (ignoreCmd config.update) config.msgDecoder NoErrors

        toModel decodeError =
            { history = History.init (Tuple.first config.init)
            , initCmd = Tuple.second config.init
            , isViewInteractive = True
            , decodeError = Maybe.map (Tuple.pair Cache) decodeError
            , decodeStrategy = UntilError
            , description = ""
            , isModelVisible = False
            , cacheThrottle = Throttle.init
            }
    in
    config.fromCache
        |> Maybe.map (noCmd << unwrapResult (toModel << Just) << Decode.decodeString decodeSession)
        |> Maybe.withDefault
            ( toModel Nothing
            , Cmd.map (UpdateApp Init) (Tuple.second config.init)
            )


mapSubscriptions :
    { msgDecoder : Decoder msg
    , subscriptions : model -> Sub msg
    , update : msg -> model -> ( model, Cmd msg )
    }
    -> Model model msg
    -> Sub (Msg model msg)
mapSubscriptions config model =
    if History.isReplay model.history then
        Sub.none

    else
        Sub.map (UpdateApp Subs) (config.subscriptions (History.currentModel model.history))


mapUpdate :
    { msgDecoder : Decoder msg
    , encodeMsg : msg -> Encode.Value
    , update : msg -> model -> ( model, Cmd msg )
    , toCache : String -> Cmd (Msg model msg)
    }
    -> Msg model msg
    -> Model model msg
    -> ( Model model msg, Cmd (Msg model msg) )
mapUpdate config msg model =
    case msg of
        DoNothing ->
            noCmd model

        UpdateApp src appMsg ->
            History.currentModel model.history
                |> config.update appMsg
                |> Tuple.second
                |> Cmd.map (UpdateApp Update)
                |> Tuple.pair { model | history = recordFromSrc src (ignoreCmd config.update) appMsg model.history }
                |> tryCacheSession config.toCache config.encodeMsg

        ResetApp ->
            Cmd.map (UpdateApp Init) model.initCmd
                |> Tuple.pair { model | history = History.reset model.history }
                |> tryCacheSession config.toCache config.encodeMsg

        ReplayApp index ->
            { model | history = History.replay (ignoreCmd config.update) index model.history }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        ToggleViewInteractive ->
            { model | isViewInteractive = not model.isViewInteractive }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        ToggleAppReplay ->
            { model | history = History.toggleReplay (ignoreCmd config.update) model.history }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        DownloadSession ->
            encodeSession config.encodeMsg model
                |> File.Download.string "devtools-session" "application/json"
                |> Tuple.pair model

        SelectSession ->
            DecodeSession
                |> File.Select.file [ "application/json" ]
                |> Tuple.pair model

        DecodeSession file ->
            let
                decodeSession =
                    model.initCmd
                        |> Tuple.pair (History.initialModel model.history)
                        |> sessionDecoder (ignoreCmd config.update) config.msgDecoder NoErrors
            in
            File.toString file
                |> Task.map (Decode.decodeString decodeSession)
                |> Task.andThen resultToTask
                |> Task.attempt SessionDecoded
                |> Tuple.pair model

        SessionDecoded result ->
            case result of
                Ok sessionModel ->
                    noCmd sessionModel
                        |> tryCacheSession config.toCache config.encodeMsg

                Err error ->
                    noCmd { model | decodeError = Just ( Upload, error ) }

        ToggleDecodeStrategy ->
            { model | decodeStrategy = nextDecodeStrategy model.decodeStrategy }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        ToggleModelVisibility ->
            { model | isModelVisible = not model.isModelVisible }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        InputDescription text ->
            { model | description = text }
                |> noCmd
                |> tryCacheSession config.toCache config.encodeMsg

        UpdateCacheThrottle tick ->
            Throttle.update
                { onTick = UpdateCacheThrottle
                , toCmd = config.toCache << encodeSession config.encodeMsg
                , tick = tick
                , throttle = model.cacheThrottle
                , args = model
                }
                |> Tuple.mapFirst (\cacheThrottle -> { model | cacheThrottle = cacheThrottle })


mapDocument :
    { encodeMsg : msg -> Encode.Value
    , printModel : model -> String
    , viewApp : model -> Browser.Document msg
    , update : msg -> model -> ( model, Cmd msg )
    }
    -> Model model msg
    -> Browser.Document (Msg model msg)
mapDocument config model =
    config.viewApp (History.currentModel model.history)
        |> (\{ title, body } -> { title = title, body = view config model body })


mapHtml :
    { encodeMsg : msg -> Encode.Value
    , printModel : model -> String
    , viewApp : model -> Html msg
    , update : msg -> model -> ( model, Cmd msg )
    }
    -> Model model msg
    -> Html (Msg model msg)
mapHtml config model =
    config.viewApp (History.currentModel model.history)
        |> List.singleton
        |> view config model
        |> Html.div []



-- DecodeStrategy


type DecodeStrategy
    = NoErrors
    | UntilError
    | SkipErrors


encodeDecodeStrategy : DecodeStrategy -> Encode.Value
encodeDecodeStrategy strategy =
    case strategy of
        NoErrors ->
            Encode.string "UntilError"

        UntilError ->
            Encode.string "SkipErrors"

        SkipErrors ->
            Encode.string "NoErrors"


decodeStrategyDecoder : Decoder DecodeStrategy
decodeStrategyDecoder =
    Decode.andThen
        (\text ->
            case text of
                "NoErrors" ->
                    Decode.succeed NoErrors

                "UntilError" ->
                    Decode.succeed UntilError

                "SkipErrors" ->
                    Decode.succeed SkipErrors

                _ ->
                    Decode.fail (text ++ " should be either 'NoErrors', 'UntilError', or 'SkipErrors'")
        )
        Decode.string


nextDecodeStrategy : DecodeStrategy -> DecodeStrategy
nextDecodeStrategy strategy =
    case strategy of
        NoErrors ->
            UntilError

        UntilError ->
            SkipErrors

        SkipErrors ->
            NoErrors


toHistoryDecoder :
    DecodeStrategy
    -> (msg -> model -> model)
    -> Decoder msg
    -> History model msg
    -> Decoder (History model msg)
toHistoryDecoder strategy =
    case strategy of
        NoErrors ->
            History.noErrorsDecoder

        UntilError ->
            History.untilErrorDecoder

        SkipErrors ->
            History.skipErrorsDecoder



-- MsgSrc


type MsgSrc
    = Init
    | Update
    | Subs
    | View
    | Url


recordFromSrc :
    MsgSrc
    -> (msg -> model -> model)
    -> msg
    -> History model msg
    -> History model msg
recordFromSrc src =
    case src of
        Init ->
            History.recordForever

        _ ->
            History.record



-- Session


type SessionSrc
    = Cache
    | Upload


tryCacheSession :
    (String -> Cmd (Msg model msg))
    -> (msg -> Encode.Value)
    -> ( Model model msg, Cmd (Msg model msg) )
    -> ( Model model msg, Cmd (Msg model msg) )
tryCacheSession toCache encodeMsg ( model, cmd ) =
    Throttle.try
        { onTick = UpdateCacheThrottle
        , toCmd = toCache << encodeSession encodeMsg
        , throttle = model.cacheThrottle
        , args = model
        }
        |> Tuple.mapBoth
            (\throttle -> { model | cacheThrottle = throttle })
            (\cacheCmd -> Cmd.batch [ cacheCmd, cmd ])


encodeSession : (msg -> Encode.Value) -> Model model msg -> String
encodeSession encodeMsg model =
    Encode.encode 0 <|
        Encode.object
            [ ( "history", History.encode encodeMsg model.history )
            , ( "isViewInteractive", Encode.bool model.isViewInteractive )
            , ( "isModelVisible", Encode.bool model.isModelVisible )
            , ( "decodeStrategy", encodeDecodeStrategy model.decodeStrategy )
            , ( "description", Encode.string model.description )
            ]


sessionDecoder :
    (msg -> model -> model)
    -> Decoder msg
    -> DecodeStrategy
    -> ( model, Cmd msg )
    -> Decoder (Model model msg)
sessionDecoder update msgDecoder strategy ( model, cmd ) =
    Decode.map5
        (\history isViewInteractive decodeStrategy description isModelVisible ->
            { history = history
            , initCmd = cmd
            , isViewInteractive = isViewInteractive
            , decodeError = Nothing
            , decodeStrategy = decodeStrategy
            , description = description
            , isModelVisible = isModelVisible
            , cacheThrottle = Throttle.init
            }
        )
        (Decode.field "history" (toHistoryDecoder strategy update msgDecoder (History.init model)))
        (Decode.field "isViewInteractive" Decode.bool)
        (Decode.field "decodeStrategy" decodeStrategyDecoder)
        (Decode.field "description" Decode.string)
        (Decode.field "isModelVisible" Decode.bool)



-- Helpers


view :
    { config
        | encodeMsg : msg -> Encode.Value
        , printModel : model -> String
        , update : msg -> model -> ( model, Cmd msg )
    }
    -> Model model msg
    -> List (Html msg)
    -> List (Html (Msg model msg))
view config model body =
    viewReplaySlider model.history
        :: viewButton ResetApp "Reset"
        :: viewButton ToggleAppReplay
            (if History.isReplay model.history then
                "Paused"

             else
                "Recoding"
            )
        :: viewButton DownloadSession "Download"
        :: viewButton SelectSession "Upload"
        :: viewButton ToggleDecodeStrategy
            (case model.decodeStrategy of
                NoErrors ->
                    "Upload all message with no errors"

                UntilError ->
                    "Upload messages until first error"

                SkipErrors ->
                    "Upload messages and skip errors"
            )
        :: viewButton ToggleViewInteractive
            (if model.isViewInteractive then
                "View Events Enabled"

             else
                "View Events Disabled"
            )
        :: viewButton ToggleModelVisibility
            (if model.isModelVisible then
                "Showing Model Overlay"

             else
                "Hiding Model Overlay"
            )
        :: viewStateCount model.history
        :: viewDescription model.description
        :: viewDecodeError model.decodeError
        :: viewModel config.printModel model.history model.isModelVisible
        :: List.map (Html.map (updateAppIf model.isViewInteractive)) body


resultToTask : Result err ok -> Task err ok
resultToTask result =
    case result of
        Ok value ->
            Task.succeed value

        Err error ->
            Task.fail error


unwrapResult : (err -> ok) -> Result err ok -> ok
unwrapResult fromError result =
    case result of
        Ok value ->
            value

        Err error ->
            fromError error


updateAppIf : Bool -> msg -> Msg model msg
updateAppIf shouldUpdate =
    if shouldUpdate then
        UpdateApp View

    else
        always DoNothing


noCmd : model -> ( model, Cmd msg )
noCmd model =
    ( model, Cmd.none )


ignoreCmd : (msg -> model -> ( model, Cmd msg )) -> msg -> model -> model
ignoreCmd update msg model =
    Tuple.first (update msg model)


viewButton : Msg model msg -> String -> Html (Msg model msg)
viewButton msg text =
    Html.button
        [ Html.Events.onClick msg
        ]
        [ Html.text text
        ]


viewModel : (model -> String) -> History model msg -> Bool -> Html (Msg model msg)
viewModel printModel history isModelVisible =
    if isModelVisible then
        Html.div []
            [ Html.text (printModel (History.currentModel history))
            ]

    else
        Html.text ""


viewDescription : String -> Html (Msg model msg)
viewDescription text =
    Html.textarea
        [ Html.Attributes.value text
        , Html.Events.onInput InputDescription
        , Html.Attributes.placeholder "You can describe what you're doing here!"
        ]
        []


viewDecodeError : Maybe ( SessionSrc, Decode.Error ) -> Html msg
viewDecodeError maybe =
    case maybe of
        Just ( src, error ) ->
            Html.div []
                [ case src of
                    Upload ->
                        Html.text "An upload failed with this error:\n"

                    Cache ->
                        Html.text "Failed to read from cache:\n"
                , Html.text (Decode.errorToString error)
                ]

        Nothing ->
            Html.text ""


viewStateCount : History model msg -> Html (Msg model msg)
viewStateCount history =
    let
        currentIndex =
            History.currentIndex history

        length =
            History.length history

        children =
            if currentIndex == length then
                Html.text (String.fromInt (length + 1)) :: []

            else
                [ Html.text (String.fromInt (currentIndex + 1))
                , Html.text "/"
                , Html.text (String.fromInt (length + 1))
                ]
    in
    Html.div [] children


viewReplaySlider : History model msg -> Html (Msg model msg)
viewReplaySlider history =
    Html.input
        [ Html.Attributes.type_ "range"
        , Html.Attributes.step (String.fromInt 1)
        , Html.Attributes.min (String.fromInt 0)
        , Html.Attributes.max (String.fromInt (History.length history))
        , Html.Attributes.value (String.fromInt (History.currentIndex history))
        , Html.Events.onInput (Maybe.withDefault DoNothing << Maybe.map ReplayApp << String.toInt)
        ]
        []
