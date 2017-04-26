object AppForm: TAppForm
  Left = 0
  Top = 0
  Caption = 'LMSoulCry'
  ClientHeight = 420
  ClientWidth = 361
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  DesignSize = (
    361
    420)
  PixelsPerInch = 96
  TextHeight = 13
  object PortLable: TLabel
    Left = 89
    Top = 38
    Width = 20
    Height = 13
    Caption = 'Port'
  end
  object ServerAddressLable: TLabel
    Left = 8
    Top = 11
    Width = 101
    Height = 13
    Caption = 'NOIP Server address'
  end
  object PortNumber: TSpinEdit
    Left = 115
    Top = 35
    Width = 67
    Height = 22
    MaxValue = 65535
    MinValue = 1
    TabOrder = 0
    Value = 5651
  end
  object Start: TButton
    Left = 8
    Top = 63
    Width = 97
    Height = 25
    Caption = 'Start'
    TabOrder = 1
    OnClick = StartClick
  end
  object Output: TMemo
    Left = 8
    Top = 94
    Width = 345
    Height = 270
    Anchors = [akLeft, akTop, akRight, akBottom]
    ScrollBars = ssVertical
    TabOrder = 2
  end
  object ServerAddressEdit: TEdit
    Left = 115
    Top = 8
    Width = 178
    Height = 21
    TabOrder = 3
    TextHint = 'Enter NOIP server address here'
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 401
    Width = 361
    Height = 19
    Panels = <>
    SimplePanel = True
  end
  object ClearIgnore: TButton
    Left = 231
    Top = 370
    Width = 122
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Clear ignore list'
    TabOrder = 5
    OnClick = ClearIgnoreClick
  end
  object CopyClipboard: TButton
    Left = 103
    Top = 370
    Width = 122
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Copy to clipboard'
    TabOrder = 6
    OnClick = CopyClipboardClick
  end
  object SocketServer: TIdTCPServer
    Bindings = <>
    DefaultPort = 0
    UseNagle = False
    OnExecute = SocketServerExecute
    Left = 40
    Top = 104
  end
  object TimerOutput: TTimer
    OnTimer = TimerOutputTimer
    Left = 112
    Top = 104
  end
end
