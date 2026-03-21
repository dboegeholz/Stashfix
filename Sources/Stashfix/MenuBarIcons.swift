import AppKit
import Foundation

// Menüleisten-Icon: Frames als eingebettete PNG-Daten (Base64)
enum MenuBarIcons {

    static let idle: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAAA5UlEQVR4nO2WMQ7CMAxFP4iJk7DQucfohTpxIY7BzMRxmIKsKFGSb2q3kt+UVnH78uVaBYIgCAJPTmL9Iurnf4n0clbWM4dUUUr401l7E2uzpLUtITGRvhTuXclnvTUiDaa0kD08g5dluXfu+4VRShgAnmqVNmvnuxZ5oZ0SLEn2MVroIby2t9TxSpjGWlimO9wOQP2j24K8FfLrrgNYJdzq2+60rRLOhejWiCkxyCHmcIKaEl7ClCzgO4cpPBKm0wXshVWygP+UGCaEt+ZwwrV/icVSYoQ84am4y5+9egVBEAR75wtdORQwDGhLcwAAAABJRU5ErkJggg==
    """)

    static let active0: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdUlEQVR4nO2WvW3DMBBGvwQpsoBrI4UXMZAJnM5tqmzgCbKE23TKBAaySsBaS6ThWacLj5RJk1RxDzBI8Ud++nCgBBiGYRg9eWD9r4z9x3uJLOWxcH/OQxYRSvh34d4X1m+WdGlJcJpIPwXGnjPv9V0ikuBAHV7DR+TL5rJbuO4aRihhAPgpd1EZfHvx7QeAt8j6Pb/QhGswsD7Jvoq5mDiANsKDuL6w/ta3TqxVxUvP4RRcdotJUCLn5ENeqS1MkMyZjZ0AbPxPrlOpWRKUUkgWAD7F9Ttb7/z+f6XRKmEpK6G0k9RKWKZ7EvM8XT63ATBinvLsWGuVMEeWwk30EObI5JP0FL5ZFugnnCUL1BOm44jeYKNvU/VL62hft2MNmGS0dEdlfEZNYZkyML0cJFxWTRdo97XmMJ3JsSRdZA5A/ZLgKTnoQnJO/VprkTD9Ob39Yimu4nuYkOKhuSSa8F4ZvwdF95Y1fAiu6s9avQzDMIy18wdcZDbNd5VeOwAAAABJRU5ErkJggg==
    """)

    static let active1: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABcklEQVR4nO2WMVLDMBBFfxgqDkFJkYbadVoukOEgOQMH8XABWmrqNCoocxIabbx8tJIjIVmF3kzGsiUlz39WioDBYDAYbMlOtT8z5h/+S2Qtd4Xzc16yiFDC3yvnPql2s6RLS0LTRPo+8Owh87u+SkQSTNLQNXxAvmwu+5XjrmGEEgaAj3IXk9lfz/56BPAaGf+ibyzhGsyqLbLP1BcTB9BGeKb7s2pLSTgaa4qX7sMptOweds1yH7/kldrCgsi8q2cnAI/+w+NMapaEpBSSBYA3uj+q8c7P/1MarRJmWUbSTrKje9nvSrc1TpdldLon6rv4qyxEedkJaJewhkvhJrYQ1nC6SbYUvlkW2E44SxaoJyzbkSwcWUip+uUFt9m2BiwyVroX4/kvagpzysDy58BoWTNdoN1pzWHZk2NJukgfgPoloVNysIW4zzyttUhYflz+/WIpdnEeFlg81JfEOkv0SPAsMQUG9kCvXoPBYDDonR9qlzf5p//ZTgAAAABJRU5ErkJggg==
    """)

    static let active2: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdElEQVR4nO2WMW4CMRBFPxFVbpEiEg1LyzGiKDW34BTcYmsUcQzaTRWJgquk8bDD4LE3Nva6mCchz6698Piy1wYMwzCMOVmw+pzw/PZZIlN5yXw+5U9m4Uv4d+KzK1ZXSzp3SnCqSC89914Tv+snRyRCRwWfw1uky6aynjjuFoYvYQA4Zavo9K69uPYTwC4w/oNfaMIl6FlNsu+iLyQOoI5wL64vrN64dhBjVfHc93AMLrvBKCiRffJP3igtTJDMkd3bA3hzHzlOZSGuaTWeUs0YlJJP1scXq2mK7DAuug6ol3BMltKOUiphma6UObB6L/qurqWUv11bNWHOIT5EZw5hjkw3ypzC/5YF5hNOkgXKCdNORQuHFlJs/soF97Dj1UyYZLR0r8r9O0oKy5SB+82Bw2XVdIF6p7UB4zs5lOQQ6ANQfkrwlAboQrJPPa3VSJh+nHa/UIpNnIcJKe7ri6KdJVrEe5boPANboFUvwzAMo3X+AKF6OI/VdTKeAAAAAElFTkSuQmCC
    """)

    static let active3: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABcklEQVR4nO2WMVLDMBBFfxgqDkFJkYbadVoukOEgOQMH8XABWmrqNCoocxIabbx8tJIjIVmF3kzGsiUlz39WioDBYDAYbMlOtT8z5h/+S2Qtd4Xzc16yiFDC3yvnPql2s6RLS0LTRPo+8Owh87u+SkQSTNLQNXxAvmwu+5XjrmGEEgaAj3IXk9lfz/56BPAaGf+ibyzhGsyqLbLP1BcTB9BGeKb7s2pLSTgaa4qX7sMptOweds1yH7/kldrCgsi8q2cnAI/+w+NMapaEpBSSBYA3uj+q8c7P/1MarRJmWUbSTrKje9nvSrc1TpdldLon6rv4qyxEedkJaJewhkvhJrYQ1nC6SbYUvlkW2E44SxaoJyzbkSwcWUip+uUFt9m2BiwyVroX4/kvagpzysDy58BoWTNdoN1pzWHZk2NJukgfgPoloVNysIW4zzyttUhYflz+/WIpdnEeFlg81JfEOkv0SPAsMQUG9kCvXoPBYDDonR9qlzf5p//ZTgAAAABJRU5ErkJggg==
    """)

    static let active4: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdUlEQVR4nO2WvW3DMBBGvwQpsoBrI4UXMZAJnM5tqmzgCbKE23TKBAaySsBaS6ThWacLj5RJk1RxDzBI8Ud++nCgBBiGYRg9eWD9r4z9x3uJLOWxcH/OQxYRSvh34d4X1m+WdGlJcJpIPwXGnjPv9V0ikuBAHV7DR+TL5rJbuO4aRihhAPgpd1EZfHvx7QeAt8j6Pb/QhGswsD7Jvoq5mDiANsKDuL6w/ta3TqxVxUvP4RRcdotJUCLn5ENeqS1MkMyZjZ0AbPxPrlOpWRKUUkgWAD7F9Ttb7/z+f6XRKmEpK6G0k9RKWKZ7EvM8XT63ATBinvLsWGuVMEeWwk30EObI5JP0FL5ZFugnnCUL1BOm44jeYKNvU/VL62hft2MNmGS0dEdlfEZNYZkyML0cJFxWTRdo97XmMJ3JsSRdZA5A/ZLgKTnoQnJO/VprkTD9Ob39Yimu4nuYkOKhuSSa8F4ZvwdF95Y1fAiu6s9avQzDMIy18wdcZDbNd5VeOwAAAABJRU5ErkJggg==
    """)

    static let active5: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdklEQVR4nO2WvW3DMBBGvwQBUrlyG8BreIlskBWMNO7iMqWbICt4Ay2RQdKy0gJpeNbpwiNl0iRV3AMMUvyRnz4cKAGGYRhGTx5Y/5yx/3gvkaU8Fu7PecgiQgn/Ltz7wvrNki4tCU4T6afA2HPmvb5LRBIcqMNr+Ih82Vx2C9ddwwglDAA/5S4qg28vvv0A8BpZv+cXmnANBtYn2TcxFxMH0EZ4ENcX1t/61om1qnjpOZyCy24xCUrknHzIK7WFCZL5YmMnABv/k+tUapYEpRSSBYBPcf3O1ju//19ptEpYykoo7SS1EpbpnsQ8T5fPbQCMmKc8O9ZaJcyRpXATPYQ5MvkkPYVvlgX6CWfJAvWE6TiiN9jo21T90jra1+1YAyYZLd1RGZ9RU1imDEwvBwmXVdMF2n2tOUxncixJF5kDUL8keEoOupCcU7/WWiRMf05vv1iKq/geJqR4aC6JJrxXxu9B0b1lDR+Cq/qzVi/DMAxj7fwBttE2ztmISuAAAAAASUVORK5CYII=
    """)

    static let active6: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdElEQVR4nO2WvW3DMBBGvwRBChceIEC28BTZIxOkcWMXduMmE3gPTZE5MgAL1Wl41unCI2XSJFXcAwxS/JGfPhwoAYZhGEZPnlj/lLH/+CiRpTwX7s95yCJCCf8u3PvG+s2SLi0JThPpl8DYa+a9LiUiCfbU4TV8RL5sLu8L193CCCUMAD/lLiqDb6++PQH4iKzf8QtNuAYD65Psp5iLiQNoIzyI6yvrb33rxFpVvPQcTsFlt5gEJXJOPuSN2sIEyXyzsQOAjf/JdSo1S4JSCskCwFlcf7H1zu//VxqtEpayEko7Sa2EZboHMc/T5XMbACPmKc+OtVYJc2Qp3EUPYY5MPklP4btlgX7CWbJAPWE6jugNNvo2Vb+0jvZ1O9aASUZLd1TGZ9QUlikD08tBwmXVdIF2X2sO05kcS9JF5gDULwmekoMuJOfUr7UWCdOf09svluIqvocJKR6aS6IJ75TxR1B0b1nD++Cq/qzVyzAMw1g7f2VkNs4SMzCuAAAAAElFTkSuQmCC
    """)

    static let active7: NSImage = makeImage("""
    iVBORw0KGgoAAAANSUhEUgAAACwAAAAsCAYAAAAehFoBAAABdklEQVR4nO2WvW3DMBBGvwQBUrlyG8BreIlskBWMNO7iMqWbICt4Ay2RQdKy0gJpeNbpwiNl0iRV3AMMUvyRnz4cKAGGYRhGTx5Y/5yx/3gvkaU8Fu7PecgiQgn/Ltz7wvrNki4tCU4T6afA2HPmvb5LRBIcqMNr+Ih82Vx2C9ddwwglDAA/5S4qg28vvv0A8BpZv+cXmnANBtYn2TcxFxMH0EZ4ENcX1t/61om1qnjpOZyCy24xCUrknHzIK7WFCZL5YmMnABv/k+tUapYEpRSSBYBPcf3O1ju//19ptEpYykoo7SS1EpbpnsQ8T5fPbQCMmKc8O9ZaJcyRpXATPYQ5MvkkPYVvlgX6CWfJAvWE6TiiN9jo21T90jra1+1YAyYZLd1RGZ9RU1imDEwvBwmXVdMF2n2tOUxncixJF5kDUL8keEoOupCcU7/WWiRMf05vv1iKq/geJqR4aC6JJrxXxu9B0b1lDR+Cq/qzVi/DMAxj7fwBttE2ztmISuAAAAAASUVORK5CYII=
    """)

    static let activeFrames: [NSImage] = [
        active0, active1, active2, active3,
        active4, active5, active6, active7
    ]

    private static func makeImage(_ b64: String) -> NSImage {
        let clean = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: clean),
              let img  = NSImage(data: data) else {
            return NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)!
        }
        img.isTemplate = true
        return img
    }
}