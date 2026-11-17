import ActivityKit
import WidgetKit
import SwiftUI
import Foundation
import UIKit

// MARK: - 内嵌插画素材
//
// 静态素材：动画原画面里「小新牵小白」整幅，抠掉草地背景后等比缩放。
// 不用逐帧动画 —— 灵动岛现在是「左边静态场景 + 右边跳动红心」，
// 所以只需要一张图；红心的跳动由主 App 定时推 frame 驱动。
//
// 直接内嵌 base64 而不是放图片资源：Widget Extension 加资源要在 Xcode 工程里
// 手工配 build phase，容易漏打包导致空白。

@available(iOS 16.1, *)
enum SignInArt {
    static let scene: UIImage? = decode(SceneBase64.data)

    /// 场景图宽高比（宽 / 高）
    static let sceneAspect: CGFloat = 437.0 / 264.0

    private static func decode(_ s: String) -> UIImage? {
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }
}

enum SceneBase64 {
    static let data: String = [
        "iVBORw0KGgoAAAANSUhEUgAAAbUAAAEICAMAAADvIJpEAAAB4FBMVEUgJBomJxOcJSUhUmOhoJdkJBSbZVZqYlbm2aCkkmUibpoeKxtkUSmj4eXXrpnc3dUeJhVjYxzk0WEikNQQOFBtbWSaUDdkjpjuyihImM4EYV/o6qTKoG3UPEXj46TINTrm5KGlp2nYXWIzj63h5OH9/QGrsKvw9HHs69JeGg7svB6rq5pbUyklVyBjbVmUlGW5wLxZYVWY5eB////o6eCcizedmmp53OsDA2fayihieIoiS0xSUi6jp50qTkoAAP+nusXdQjx3gXaf6+f/qgCe4d0A//9MMhD/AAD/rVzW1nVjpZ9skGY1QTvf2HsKO0OIdluYpSUbdcG1zXf/tLS635r/f3+hPkQ8QRjUqtQ5QT3Iu3l/f/+HeEK/fz+/AD+VhD7KyB6GiDN/1H9BP0FNh3+CZTEA/wBVAFV5ioh2opy9wX4AAADv+fvwvaLpNkEEAwbr60/xu5t05fjyxqzqNj3mRE7v8VP307fYR0wDAgD///4DBAD518Uzlc8EBQICAgD4+Y319nDr6mvvxA2wt7WL6PHN1tZQWFUyNzQRFg1wdnOQl5UGBgLQVFXm7OpxGA7a5+dNNg8QRlAsFxCNFhQxhrFISkcUFw7Op5JSKA4UFwgTFwhORS5XZWdMNy0r++v0AAAAoHRSTlPoGf77/v3++/j9/qP8+/73XQ7+/vcP/f79/AUg/P5a/qIO/v2eAQwKHAz+XKMZbGb+mSoCW/6d/gOl/59bl2AB////ogNpAasBA2cMF/ydphYW/h0DGAL+Twa/lwK8BASmf24GhEK/AQNlm4UA/v7+/v7+/v7//v7+/jACcP79jU79/v7+/v3+/Pqy/v6s/vv+/vb3/v7+98/+/I5z+vz+RnWRiQAAKX1JREFUeNrtnYd72ljW8C9IqFiiOWCSuMROcZJJ301m5ksy/d3ZKTuz5a1f713GDFE8MiVgezHdPbGN27/6niuJLkACCcM+Os+u4xY7ox+n3HPOPQcJfcjdu3fg7cL0PWF6bm56eu6J3+8A8fv/JNgyDEHG/0ocvwFWc/NPXr9+yJ2cFBCKyIKOTk58Dv9dv3/BfrIjRO1OXLgDSjY3N/fgMcepsFqlHEHlcgH42exGgVowCP8X7s1NP3l40oFYkxydOuwnfLnU",
        "4tPADFzZQtBX1oNMsZm++/YzvkRq2Jvdez735PQoYkiQrW6XRm06LkzPz3/2rNAZz0EnLxe0uV0KNaxncwzLdzGMB7THc6D9JS6+ELQf9NCp3QVdmy+ddTGDB9SxtER2spGv4/ZzvgRdm54ncz2YSWLysHNIYtvI4VKLL8LxbJ7uYhsR7UlKYlRiDjraThb5bHUbIjV42P65Oa6LotEeUQyLQK3RQCKEXBcXPE1TFHUsJpMe/sRWt6FRg8hxLv663JmZixWTYjgaDoeTDdQQ6fEASVESwXICVHiftU8Aw6J2F6A9OOkaOCbFaJRhAFuSqn+eSopYmCgDODHTqCiRKG0/7WFQCwK0x1082gUJdGRoAMZL17/AStEWAarHyGc/buupLQI0XzdoHmwcgVpUD7Vw0nPmw7lnW6zVtXvT3cKQCAvQMDX5/2KygdqxJHOSv1IXSTx7eE/w28/cSmqL011jx0iElLDXEjGeZmoHHrFV0+S3knjB2U/cSmp3hPiD7nliFJbto0pETNZzJwi8XbhZFHriMXptP3JLdc3foxxzJnWidqGcBdqpRSUW+W0baSG1YK+KDK24NQ1q8JUO1KISxf3BrrhZRs3fs4zGJsMdqUU7UQP3Z8f/llEL9q59kslwBwtJdaTGhEVm71/sp24FNb8eaHII2UjtsOErnXUtDK4taLs2K3RND7QDTws1uinw70ANuEm0Hf5bQU0PtIgLZ4UbpE7tQmynVoMHBzwGEsm2splNza+rn+ci2QwkWawFI1InaIpILGdX28ymFj/R1XtFt1JjG7KQXZiJYCN5O/1vNjWfvo45qoVarSqK3Vo3VQtDARU5ggsL8Tt35Fzyd3fslPKg1Bw6+xyVLGSDDolnVQMpMuHukqQTrb/Vb5MbgJpfb5PqcasdlI6RUsfu4dYwYQ96gi/jTP/9Apa708qvtsH1SS1YiOim1qpr4jHWNgpUTYOa2BRyShTP8vxeVRDn89tRZf/UTvVCA+/VBiYpUhTZciAQq0QpNio2MGSpKYpi2RnPzAzLUhS/h058uNf1kY3EIDW/cF93+/6FKGoqlCS2fUFMhoEKz9Y1MBqW+0qgF0juB4I/JM8xdWb3Tfalawu67aNcp9E8RbdWaUQpTLlc0F/X8v1VJVRTKyJoKkkjpQHPPs4ZoebTDa3tuKb0G8gsxGbtA2YsVsGwhnaK",
        "arKr+r0eds9unDRI7bWBC06UFNZMNSpPX1QxgJ7xMrO2eKRDcCl5KOT7Q9y+ZKqbWrxggBrbBYGodq6KHr7iosKSKDay7Hj4lnPLosTQ+DqHHVLqpGbAPkLg35WarDYsX5mawbaRYcI6dS0sF07tawH6qS0YuQSqEfg3OiuILTxTFRyCyD3ITFivyJ4ROicLC7a26aJ2YkTVLkSxczFGxO6pMnWsurNwOBo2IPDNEtTg7KBEDzWHEWiRs47mDnQrylIVF1tjFo5GjSBTohK2YGPTQc2QqkX4TslGnAWB45kHwsdwLdg3TA0X4exLOL2pGVM1SOwzGg8cQo8ZVwUjaz6eGbKQyt8Qk6RtJHtSOzVGjdLQNRzqu5RIXww3namNUlMaUVjO7njtTs2gqmnWq8E2QtionM6a4/yoYWhRrG0Ut2DfwelG7cQgNaiutSWJZ1z8sSSGBxeFGmDjuXs2oc7U/MgYNGira9ef42PRDGb1tKbI8D7bRnam5jOoaki7ThMOm8ctKveioE+/sBl1olYwSO1MMlGrOuuayFB2x2sHan7DsQgO/KNhy7nhbNiZ3fHaSdc4o9Rw4G89tjC+FWArWwdqC0cR44G/Qs1qeLKy2aJFzbCBjOjonjPJt0lUwoakSS3dPcq/gLlK9EXjlKyDY2kY0GTfRnK2X9Okdtp9Hh3MwYJpMB7qoIGaODRqybOYTUmLWqHr+B45rQglMxhh1u2GmlWStE2kduTfMTGCKLhtVp0ZAm2LVMNoimFRAxN518bUTq1jMIJYsXHcC6ThqZ73Cs2nxuzZlDSodXJrB6QkNk3CqmHjh0lNsqcmaFErdB5NoU7Cql8YVO7x8mJ0aNQg9j8V7DNbK7VObo2ua1q9hCJKF+od3uFQw5129oVgDWq+TrflpWg7tWgSz3/XGANjITXS7iBpp3bSeQhMuI2aMqGCkoZHDV9RtDG1UUtpq5pXDLfpGi56eUHZWGl4bg2nIm1MOqmRYliDGg5JvNQQdU1OIMPIBDur1UztH8odLxVqUoOmngorDpOaxCfsILKF2v1OEw7Uu2XtxRjxOBq2qV0uNYfRyxfN1wqHkYm0qemjRktDJtOt6QdTs0UHNTYZtqmNG7WD41FRNfmihj12q41aUMcUwcvVNZG3MbVSe6Ll1rwjRA2ufNiY9OgaNTJuDSes7YxWO7XFsp6xFJeI",
        "TSLtlkhdGS1Sio4ONZE9sRNabdTKWiFkdARMo3IhKoxr2Ta13rrWc5rq8KjhuTG8nRjRRS0shkeEGiPaRVFNaqcGs5DDVTVGok/sBoR2ag4NvyaNDjX7eoZOam2TqC8Rm+Th7PGsGtT+dDSy5zV8p8buhtTbD1mlFr3EkF/Ji0A6y74sqkmtvbWOV7LH0ejlWUalAcLjpbhpG5K+Pv8Lw/OvTE/0q7rGoCfT9hhkLWrtM1irQeQlUVMnlQM0L52Ytuf7aN9f82kk/cXLo4ZvOFIs3CqISox9wu5IrX3fGvKIl6Zp3mMXCKrMiHJ3lh2KdJpc4dNa0BtlGmdPD82biRgaDTMm0bGXPgrahDpSa18pdHBc2548XGqi6EIuysXT9AHNIntJs7E5WheMdDnUQNUop9Ppoi8iR7ZT60otznVoiVQGdDaNfLeYmsfFT8nU8hE7K9JjPqTG2jU6mdQ5hN9cagc4GHHxZ0f2UP9e8yG1sB16koqiic1LMay7qqbomovmadjsZZtHHTPG/ZrDRsTWVUGsaCUz/EuoA3RxgZAd8evawqBx0xfRHjzWR17OhRMWJI8o0YpCt5ovltdpi8d0BJ3a0PRRu6t11feAJj3eJMz3SeL1aAdKc4JoXQ0UTztO0vYGBgM7obTHRB6c0Xj82aE8KoEWrW0TgaWHNDq1E48G9q/Fe0/3JJOW3sDGzOy1eYao3RHiPn3bRC3JUHqTDKyoPLWZGd/h6yj3WkiveVd70FZ+vBjWQ7u4hM3MOLW4EJ/+l6OuW9eiplOTV/mS7Bk6tWn0u+V8Wrh/2nHyIN08w05jw2GXnZXKCV2sns6UKB8TY0iK507Ttpr1TU0xkx24qaoW7kvbxPrOoag69h2AeYAY4k7tcauDUVNyf35fQWvGp2jOrDpV8zwsfYYKCZuYObomn7nbFe5CWUnek0eLTWz4SP2cxzNzk5pyVQ74x/LvsqtoZlGTFe6kCRwl9rSLNVZRedGhKuC7cPtOVKZFQR3mPQiuxvDMnOCwW4tNpSZrnO+0jKqVG0k0JmHQKpAZzAoqnTs7Oy6Z1uzsCsjNm+9ha/1c3G7BMpuaonMOH4cOEHWTYmdmZjw1aR4cGVUJyYioqSknrm3uYMHlMlm5bsyurqiyvLy8etP53uma+sHu57GEGsi0ROEHD7LjUjC4XDt1ce68x1bP5XxfE2dV",
        "bszOroLUYNVlZfU9BR0i/yj4bW0zn9odv2NedDpXV+XHP3vDeeOGs0VuqPJVjU9dljvKitN5c9XF/dmmYAG1u8Ic43RWH/9Kmyy3M3r7drm3vF3BL4UtV+WHeNDWNpOp3Yn/eZ5yrVZ15m2NyFtVqp962yI9sa2sYmzUDv+DsGCTMJdaXPh5ZsdZM3R1Hq103r41yG119T1Quwm+bc4OScyldle4y0y9B2g1FVtuxrS83AFbT11bXXW64BAA2KbmBLvL2Exqcf/8zPtVxVf1hGGEmWoiwS3ehAPAtI3NRGpBYXrGKdvHt3qCDH20qtCWwUTiYAZ07r/EBXuJkGnUIIBk3690J9U3tRWIImfhh6+uOCtPBDtJYha1O8LdSZfTImrLsys3nIqybTkrr+/ZRtIkat8LP8zszFpFrerYwFRuOV0PbWym6drPU71U7e1bzfd1CTi2WflsPgshycNp20iaQQ3HIjs3lk2j1hxivpWTWjfUZPKWjc0kagsQi7iWraCmklvFjk2mtrKCsdmnbVOozU85raKmpkfeV6mBkzt4bRMxwa/Ff3aZSa09isSpSMVvfvX27aoTrtLY2jYgNeiPZF03rKZ2oxrtfAUFAPt+6MDU7grT7M6sldSWV2edtRj1q+UVihO+s6EMRm1amKPkHKSF1OomcvmrFUzNjiIHtpDzvU5rg1JbhvRI1URCiZS3LeSg1OCSDeOymlqDiVzdouzb2GZQm+np1galVosiV6CsXbFvaJhBrXcwUj2F9UttWc37w3GNctlbMgantgghpGtW37MfgJpiIlewfbT7kAenBvmsKdeKEQL9UMPpkVXZqbkK9lwYc6i9t5zasuzYMDT+LPVvbSImUON1UbtxYyBqGNsWteMSGTpl57MGpeYX/n3vwF9RlpWBqL13YmjHcPuG5ezQf+Ds8ce4EfKtjth9EGpAfefmTsUDC+8BG7JvIQ5O7cZKz4zWMg4nVgagtuLccVWOJXVXBjq1Y5JBqc2uzOoLJwbRNZiXC5oWVrHxXNwu1wxC7T8CtVVd5+SBLOTWDp8MV2/piwx/YnMZhNrDnRV92Y0bg+jaLKYmXwtW9+TRJ/aak0Go6Qr8VwekBthdYsMMNFGioKZtB5OjTo2CsL9h4iDDsHbyv//6mksftdkBqS2vutgqNfmNKJF7dqWtL2pB4e/3uh2ya5n+OrW+",
        "BH7K6g4lRuvDPYGd5Dn7m6zaxONxa6nd0U2Ncg1KzTUlRhug4ROAyKuTIv3Bfwr+bbSS/0OsPj7JQgv5+x7Uls2i5nSFxWZqEEqCc/sbOnA7YukyKvh8aUGIxQb8D+tG7TuBc27puHIxIDWcXVHCkSZqYTEJ07E5LL/nCokx17ZY4ugwRD7Ner23nz/47LFMzqoY0ufaglkUvY5bNyGGXB6E2lugNiNGWyQclkSKp1nSI3pI2A41zsxSiM5sL2HJZvGfgO7xaTqWTltBzc9VKGprtXNSC0bArOBKy+zyQNigfZWSRHVuZKOVlJQNejCK6yw9tqYxncqHvDIy9zkCIeX3vbdvf/YM5H9w6CiVSMdM7Bj/71zFNUWtrirjedqvn2FxDqhqMrUdXp29FdUWWKAXG1M1Ozos1ZjlShl3kcguNch2NuvNhHIIpfQPNu11wzcOg+tQxekElQNZ3VIBKn9gYO8HhgZuc3bLhf60MD03L4+3Y5rtpDozni3cH0NvVjj82i0bRjKUy+cyMqfdJQ3JPiUPkd5hmTpm+1x3cAfIpQ7PUkcw4Rl0TnVY1uzKyqDUlm865fas04c062HkwYTq0NdaukSU6DFzbY4EOi/JyJbIXD6fK2WXeshTGhTOLx+VTZh+FqcrvItiYRYdz7tq48+UAVrLAzJTqK1OcfH7d4P41cmhZx/L6JpmLONaADdW23x9R0UVkzd3WHLvLumRbIlQp9N+OjC1bx+6bu54krVRqsceaoea1fJ0A1D7Q/33pQvojKfI2mxsZb61yI+TZ/MdelUSZL60ZECehg65k7QZkwaBmpOqjcMNi17qffdxdIap1XvFlZxPLHaKWElZFSVPuYYkF3s6PoWANF1VrhKRWTIoWVhHUUgMTM0H1Hip/tIXnU6TkKnUVqhKOxCOxFF/EouXOoaMsk8YlzbXdK4OLbvUh+xmckcpx2DUfu+EEQXVyAC/8k2ntlXRiMDOkkkYHU/RIHjAOVkYF01L1KCReU1oWR1uLltECX//1O5jatSOp77z0LNzw0Rq+M2Whq4JHGzyvYDZvTSMXa6EpQw6vT4OzBYT51Wflg2QGjzI85Ku4MSbK8cGo7a1MyNF69RWzabmandacTpycQbQkhLFkxesN4P29+XyzWizmy7nqtCWchqBSIbOkbs6DSWJNPt69VD7Lo6pOSmpqmtSw5RP",
        "06idtFF7hiKkl2TlyNXLXiTJQOjlPvKNeEQSLNO1h35ebNef83Mj0UkGoXKiLWmiZ8a48I/QgrzldNaWKkjUe/OgddC168L/3CfyeBy9WgHg82ji2rUrEwRw+36E9a0B2stcu/IQho4B3iJCBE1EEtNGqQWFBajEwAyXqEpNlKbMpLasRe268CNBXAug2plNlJ6h/YkP794Bt8AI95UXQrVHHspttwYYdM5QRJklCBL/jEw+ZZxaEAziVj0cMTeEVKlNcb9tVrVXxIdQAJHy2Z6BVAnzPOXzEcSHa9euTUzsc77gCOpbUCjUow8y1+q93JqxSRdNy1f1djuXiBu1kI8q+KqSq3rOFsM7FlBDzar2h/2JawQR+An6tVgPLGijn/hxJHKCiA+3sMIBN8focUuFGmzhoNCWzusWNttU8tBHzYWpOaeqm4OGQe0VEZogQkQEocIRd48+SsUcDmxDoYxPTLyTDSVncWDiEGLpWMxIGi192KBprbYwaxQamW/gXkwZo3ZfcLjwbgW5t0Omdmxm4K9JTVgkQNUmQviTX3waExqfXSyBCFC3d+8+qNwsUrg04p49e/DgwWJc0EkuiDJLHU/X24clY9C2842UMxFHX9S2djySBcc1LWrXhUf7HybAFnLVIUMt20/BTmJuEFCeWJRSDqbyGfmlvn07qLPsFU/Qdb1qC+8PiwaTWqXDpg/zqUVjFtK/g0dvgmNLytomzuysLlusa58T7yYm3k2cdMgXV+0k6BuSAxOzFS5eKKoB4O3HZX0NtfEYqukXHWpVHOJ8aRBVAxMZOTVIzYVHb9Ycm0jtbJlNbbWZGhhIoHaNSHV2OqdwEJC5TcDJG3/GzMxy/LSmNs90LxZOFOuqlm0N4Wmj+WN3frflvH0UM0Dtn+C85lwBG0mpji1JOW9aSu1H4fH+B5laumutuLA/cUvhxp0+MlXdEof1KEDv7Z7YUS2RVWxRLDcRMpz1L7X8DC9ROjJ0XpvmYXkTNpGsZCG1Rl15TFyZmLhyjejuUO4njvZVB7ePOBOhOVAVAFvW3YiZohuiv2Y1yZOGobWlMLdpL1n269/kJcT/lwsXrqEyiq+ZmU0NZ7TebjVTe0XAUfrau/1Yz661AgSUcPCGwCSgHATMgJeqPmVG/92eOOeu6wVqDEZKgYxxaEttFXBvthb+68v5f1z5562vVm7+s0vZ",
        "eU11Oa4ZWHiifvtXeMjg1lR9RAwME4W4PzDx7tZ+7+DtP8NBQM50Abd9k05wdVXLpQ1UrxtDB6Ihi0V4+4CWRRr6uX2Y1k3tfwv3fg9NyLAJdEc2kVI3XTNATfnOG/JtUeos0WCSITEyQVzRRU3tMyGwh4PDAuIc/oE1Ll3NSZBcUPddmUKjQu0SagnbXcwX+4G25EZfapUAjhxf6K1lQ/644txavQltCIquvTclhvzqRnXS+NaUq8EUXReu74fAremmJnwHLdlyRHnlw0SgBu7bfqmdVF/mOQOHwcOWgiYK5M5zdO7cvdSXZJAmbDqlvwMhCP0+U9TNm66K3HrjeW/KKVvuhYXeWMrpqpwVGqk59sGtAYT9mJGGUXz0vnIFwhgA9yg4gMYhNebOcPq3eaRbD9GZ4mHuJZld6lOySNMZeo8cBqjdRQeVigvJlVFMra+uupXZ6mpYtXcZL/t1VSr8lGfeV78//ymcsTG1K0aoYYU7BUP54YpsKfcDf/z8R8ytD3CxqtrQMb0NmHGh4F4yVzr048meFun9T/GdsVSlokQjYRfuH1+tii6Aq6piba1OyQJLzl07lUplj2cnNxjvxw18PhV8BCQhrxikhsMI2BFN3MLFnA/gGIlX/V2fSuerL/c+9NM0KWmfFsjytH5qceFjr5eClJa8gN61M4WXzE9N4fZ/DKOmQM2LYqtatSJ/j4oK2pYB1h7PT7HszOTG2tr6+hrzONaYhQRqAaB2Zd94kjGGcyahK0pVIPDq86Bxhatm7jMpA7/2fMls2e5Qc3Pop7YoPPR6LqAuGsXUZmAaD279ryjN/y6l4X+qLrWdzMqHFMaFhZ8CVCw7OTm5sbG+hoGtr//6K1DjmqhxEyFM7R2R6OvmkRpSwiEOnwYc3wnGfFw1hDRCLV1cGpIUE/qpBQWOobFXk6mBHFcoZnJyhmVfvJji+b29vYos6i0OFw+6hD+L39+rYFwvMKs1lVRVfgHB1OZ9QjO1D4EPV650y0P2sOdgKSdCcPiG2IR45VOPccHrhnSNvFxd69RRXljUTc0vcCzvwV0c2ESGcdMUDwDWVNmYlGVmhlVVSdYm+bPKJzYUSr+q8ktN8EdALd1M7cOHABjIK31Tg1vQCRQA36jkl0HjuEcLujUObRumJjzbHhI175lDfzQi+HD7b1SMKtDCXpJf26g9dkUUgvDO",
        "xsZ6i2z80lHgrzMfN7ZFYGoTmNq7/qnJ4E4xuA9Y4+Sokvt8sddlFZVa1ii1uODLWsZpu9QUnxZPDVBzHOBLLoxKLcnQPLP+S4Pa4HdBvVqJNEonbuvM41Zdmwi8G5QazsXBJXZ8GoBDhBycQHTi13/KLqUMNCv4MtZRa66CZ06MUMsrXW5hbCVhqkSEZ9Y2OgHq8dk2ag8FwXRdq4GTg5NbuJdSPsf57veKTmIqtYQBamnSOqPYfKjIcgaoxc6UW9P4UpJIHkSKZ2zdRHYmokfWGF8ztT+aR62aqFQyzHJ0glNe8a7cPlMsZKyfo7nlkkVPdFP7wkdLyu0/XKuhyUyRPGOYQagpEaRMbf7E36ZrfzGRGr7UXkb7xK1b7/AJnNhHgVfKQU6bnJK+J438An/h6bDCEe61fl3jaK+oXtwUPRdQ6ynR9NpG/wq2vjGpesGNtY/TQlsMOWEqNZncCYCDg9y1d7fAx0G/idDJVCrUSsb0uTg0ag7d1IIowooSvtYuQlmUxtcMSDQ5ALb1SX5S0bYN5mErtYkrFlCTnRwnRyc45UXs/5H7/Po9LXBKEFkyYiG/CHLZ0aN2egh3yY6VE3byEGfqQiUIIwegtsGza6qB9PlaqckZrXf7JlNTigMADhrPcR0Vq5zP1570SslBG2lsMM0pPRxqt326qTng5XeIXKQX+u6TngtUUpSN6V/Z1td4JZzZWJtvboP6VOBwzh+oBdIWjQGBchzuPL8i57zgICeHlZ/W3JxSlyaNvWYcBXLUdC1GL2UPsyxiaYRoniXPIBXwkqT5tfV+qW2sqX8b3FpquuVEr1D7YOE8nzRMvyGIW5D1ugWXPQKc79Ej9SUTdMQd+D/PyHlNeUbIOxRqad2R/0lmqZhbYhHPsxT/gmHOSFz3Y8Cz9U+NVaitM89aD0YxuSp65ZalU5jux9IpDsKTD7euqSqnVAjk0MsrF0XuGh18MGLUoKXyJ3LpjGUYSDquw0UXiJh2z7O5qrIZD/7r1ObbenQcgWt/+QvWNUGwemjjaQF0LhS69k6uyO3/8dXnnwfjca5ktL6G1XSxPAwbeVsvtXj6HAo72Qz2Y7KsMWcQMRVLEEauN+ZADFFjEIv/MjOX9rdRw9W1K7dOhS8shXa97uVuyf15HzC5QIAmEE79HcYMDhNyHA0B2wPdugYNgiW0VOSrwcfGGg+v",
        "xkwuW40D+6cGbq09c8RNyB0gQxjm80juCUpD2isAbu6W3L8A6FBgVylljZ5rg7I/0vkaymK3lmNrXmyNzeEm5ixEFP1SW2d4oLax0e7WqtSI2HBnAhZkN4fTJ9dCgZdeaEY9qU1cbp0y3aEB7DRv+amN1lsVxXVC6D5BX2NEOKOxsSZHkeckedaYjDSCbR30FZCDymm0nvoIOQ05RGrfqmcCHFpCgBIKoSJ0t0UiqFwuJ5Trc7EG6fhzEnnLtG13d3sbV0X9OqnBbZFdwuuFNL/i1jYYxot714vFrJof+bUPZWNomdq8BjUHAsd2ixCGK9fr5PbBSObzxPk5Xfy6eJ4jCI77d3n4RI4uFulDIo8KspTTqtQxnqKSNcyKefgXHZ7ny3onDZZL0Ja5G0KIqYrXizu/3EQ2D0fljf6oQRC5DnXsz7S8B2RHrsCdw2+FYcun1aahI9Q4zGVXlvqH3gwJUiqFAOI5UM3DLNWEkhPww4xjC8xkJqIKuq9T1yDFRiICoQjN4H8t+/XXxVwEv6TgX/uQgfj9V8zNqINbYxHUvJlnWgvXYvuha0RiRC7G69GEbKZ0ngd23MnJUSQSePml2YYyS1Sx6YxGfHBaK+FpJQQetgwpBTjguGl8pKQRUXjArLeXQXVSm1xfn9ceHpIiJi5z0nE8drjdj+fJup+SZA4eUYAw/RAACkOjSFlfj1bckfoJX6Rzu92bm275rfzHPhiMEOkNpebW1vujNn80ucbMa9/F/D/p1CVC+2KhMEhHAR2AAQ6Bl27TzaRXWUyBdDSy/N9zuNdDhNxv3rzZlKG9kd8j9s8JAj4OJeY2fumPWgFyLU9SwgjKYKXp3X1CvlH30lwzub2d03kTKi5w7tC+OxRwY2oNsukOwcwkrH45HyN7NuPUEqx33pfu2ItxiZIYzL65A4TcX0S8/HLXax606rG/t675Qm5Qq0Bo800LNdlMytpXeFC3kcao0d65UVS1oJI+HkAgeIMDJ+4Lg27aL92mkNsuVq8b96ZGgBvb/OSTFk2T5ROVHp2Y74saw+Vu+0Zz3jsatCmVDARwexHULkDjgJwJ3Eq122I9qcVCcvTxyZvOsulGT2RqvzZTa4b36y+/tukahxZOR3H8XNyEJpAsXW2hla/UwVlg1yxovahdxwbyTQ/ZdJ/7cPTfEEjWtK45TKkdsOWyATPPjWQk",
        "AoUGzoyGKxLaZpV+PqWHFgI6rynQelPj3D2pfeImU/PrXQ1j/QsysDWMbH5uelTnqsZMKm9+CduEoBETV52wkwtgcH2Sa4TW20ISm5tveisberKGr1788muHTn6Vp5zBZNbmZWIjvOTpxLQTcraUC2BLibHJLbRQD3pJGgbnbZ6v3otajHDroYaD/40mnWrVM/m6GjM3Pf3kyWOffH72x0d2Ex4yM4+YxZaSwNMBwMXh4l0A61zGiJfzPm6e7d+LWjrUNRBRxR1KzeMq9/pGk1Qv1+DboGATGRbvLInF0g7HwuIor5wxvfvbXaIxKrhtAJchb324RQQgCXyuV+W8t1+3zKtGPS4dJEI6dO0NHNnmcCVgrVVqNYKZGQou9dKc/64w+pIOLZkuXvI8gIAcIR8FAsAMKi/0Ux3IPnucbu2E6EUtpYsaODbfgwdzc9P/X751OKOi8pAsq1wZBeHZY4l5PBZrnRIWVci+LJ0DL5BAjlSGW+QPi589v317uyYtxJ4/gfWxMYPz/CGE/MT9Rg+1V2UHLvCeoCokLBcockFTFDsz4zmGuzhwZ5Eei7VOKStvNWUzGe9uPRssJxnuVQUIyvL8+YMH9+75wZvE+tmdwbk3P9FD7Rk+eU3HfXuMxEQ9x8dY5WDh1wHpFVWR90zSY7EdFFl3g7BVDh3xoJb5ScgVD4ejvz01SI+BhBPbM/WK7h4jhqucYIcrrCtp2g7KpmxqTalFZeYTdGAqsqgKHszdZYt9T2qbeqi92fx/qhLtNW7hFUVUEcUmagmb2lLrHAqzNy/jQ/YbXdTU+yeOvajYSM0VOR5DakfuoVErWUNNTzDy5pNNd0Kl5mmk5sGX3sbQQmbHm1pMH7U3m9/UdK1xSbnnokI1UmOK42Ehd4fl1pbIRD/V3x7U0j/ptJC/izlUXQt76tTYi4tGagyTH4fIP5bfHpquwRiKT83XNb3RiErNjxr9mERFLsKNH7OFcVjnms4vDY9awW+BX0Nutz4LqSjRAppppkYnazElnOTGQtUat81YLmQqfnnU3Ipfg2lbVWp4yIUEKyY9Us1eSnRqPBbwFpfGOxpxoJA+XftdQslbnnhEDx5sB7vQo9EkfXAGOwDEqn1E47HuOlUac2o6s8dvNn+T/lGl5k2qInmlC2qbrPCeJFY8UTobk93y5cy4U0uc66rUfKMUOqFGQJMs",
        "vglAwZpr2ASaxF0vBxTeDjomZzXImI8/tZgex7a5uRhTjV8KXeQvQODNYRGpk40Ozsikl0T9xLgjc8jOWnOGIy2hJiR6tyBsutW4H1tIpnFCnvqi9dLojEK+8WAmxH7SgpZ3W3Vei1tAzV/o5dkAWkMVtYHa17mGDcKR8sK4UNMK/DWWKJsiTMESapBL7YoNOsZ/J/ymTu1pwzTsTNNlkDGBpj01JGCRr8tYkdFS9oqFsG/7pK1ZHHLG0JX8zeP6VaYmaqGGl+fuYXpcoAmpolZDqkVJLov8mhwK4wtPmw3BhyzwuW9+s7jY0mfytL5hMdNhA+0Y9h/krDrCWUhNSCC6fnFNQfbNN9/87jH+2m87UCNzTauM4uMCbbHcHne4id2xqorWuBVePf5No8i20/Fj8NsOulYLIOXRRuNjHzWzkOeWTevvz3MYGBXVnNn47W81+hqAWpVViWg4ASTGB5rAZfRtsDOnwJYXLKaGSdUk3ql/snpEa5i6UUwFx4ZZsFzSikUsK4si66kJvQekq+e1ErQe1Pe/jU3QL/ypXFwaYiyytDsi1LCuMfwey+5RjGpeTsfIqeU1wo4SsfS3Ts2zxFD81AzsrOEVbrkIOh0TZYs7NHvqiHwGIugvyVKRJDOZp16YKEIW4X3v7t+OhSQR/9FVENgrxO/RJB2BkUBjUqKJl0OaF+NzORjac1ROgBSOjtBRAb+XKKNDGmYyYZJebza7u93X/JARoAZH1Av0YvLqX0E+Am4v+D3EzzBoTKgltOb57AZKS9ufpdIa9iKWTsBEO6RIHhhW14jCiJ8MHrFV/DpUyni79Ol5j0aDWoTdkKHJ3ADczCTDlsfjiK05JHA79xLePndUF5qpky2a4KkCCNFhDuQQcYVyVQocgkF35Jea9tTdV/LYfGqImaxSu3r1I9lSno3FcS2YONRSiiI+YHsXBX/nq/ftBJu/wxdBeC4aTAn82t22/3o0dA0xG1er2AAc/G8SpcdA14KFnJYyKFmR24av/dfXKjr+gw/G6m5nYXZZMYdaHCcZcYwANT9Ce3jVYc1IYmp8ahygaR3UttVU1pOBXncN6ehMS5aF7M95mEstLuS24XZonRtQ++vk5OhHI/GEVlFtlz5Xd4zETIpxipFm31lKjYKF9CGS8dAHTfr2140XZb8w6k3iGubRTagobw/gmP2JQ2+DG/Ol",
        "cs1NrCNAbaEMN3x5HoY8Y25XP1Kd2yQ/4tiCRxop41DNCc0l+k4T+MsN7vIp5Paaz4QjQe0EjOPMRy9gGzOPpmrYrkKehBvp9EirffTCNFwU+br64VxsAGh18+iWC1aOxlfIKFBzoMnJv15VEiMv9lyQ1gLHpoT//CgnI/2pRlXbztAIhsE7TmuBw4O+qaUaoGVU995ojUMjQO1kCtSrrl8VrG7KMeDq5AtOGFkrGStXXY8XZofnjhItvVqLfc/bgLzmdi0xVmWfyA3amWEmtUdoZvKjjz66Wo34IZ81NVlLb/034T+NLLUCUNsm6dxhHp1Uc1fx2uXD2/1X4lO0/DPgtJarB9KO1IPqq4S+fGppvhaAyDI5OVXhZ7C6wacnf06MbvyfePD8AZdKJNLNPilTDSEdA2QdYG0DJJ/LjT/DkX6uamDu8qmlHv6ieDXFLII325jkIZkMAro27xvdxBZ+oiqxYP3pVqO9zwb6h8urNVqTZ77bKrX05eva47v/9d+ocvWq/McPPzzhED68TW7MO0b5rB3XXCmgmrGYGYNCm14lKWUj91Kf+Qer9tJN16ecpRHiP/55/uPU+DQiVHejyxrxmQUJOUfqNowM377d590HU6kF7/75+79TBD76u++///6uHyJHRzpVhipGbMygwZqh+PPb3tsOKyx7+vXz5/fuLfb5t/8VQJsUmpsV3f8AAAAASUVORK5CYII=",
    ].joined()
}

// MARK: - 主题色

@available(iOS 16.1, *)
enum ShinColor {
    static let yellow = Color(red: 1.00, green: 0.82, blue: 0.24)
    static let red = Color(red: 0.90, green: 0.19, blue: 0.15)
    /// 红心：比纯红更亮一点，在黑色灵动岛上更醒目
    static let heart = Color(red: 1.00, green: 0.24, blue: 0.36)
}

// MARK: - 视图

/// 静态「小新牵小白」，只按高度等比缩放，不参与任何动画。
@available(iOS 16.1, *)
struct ShinchanSceneView: View {
    var height: CGFloat

    private var width: CGFloat { height * SignInArt.sceneAspect }

    var body: some View {
        Group {
            if let img = SignInArt.scene {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
            } else {
                Color.clear.frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
    }
}

/// 跳动的红心。
///
/// Live Activity 的视图不能自己播放动画（系统只做快照渲染），
/// 所以由主 App 每 0.4 秒推一帧 frame：正常 → 胀大 → 回落 → 微缩，
/// 1.6 秒一次，看起来是在「扑通扑通」跳。
@available(iOS 16.1, *)
struct BeatingHeartView: View {
    var frame: Int
    var size: CGFloat

    private var phase: Int { ((frame % 4) + 4) % 4 }

    private var scale: CGFloat {
        switch phase {
        case 0: return 1.00
        case 1: return 1.26
        case 2: return 1.08
        default: return 0.94
        }
    }

    /// 光晕强度跟着跳动走，放大时更亮
    private var glow: Double {
        switch phase {
        case 1: return 0.80
        case 2: return 0.45
        default: return 0.20
        }
    }

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundColor(ShinColor.heart)
            .shadow(color: ShinColor.heart.opacity(glow), radius: 3.5)
            .scaleEffect(scale)
            .frame(width: size * 1.35, height: size * 1.35)
    }
}

// MARK: - 锁屏 / 展开卡片（静态）

@available(iOS 16.1, *)
struct PetLockScreenView: View {
    let state: SignInActivityAttributes.ContentState

    private var headline: String {
        if state.statusText.contains("成功") { return "刚刚帮你签到成功啦～" }
        if state.statusText.contains("手动") { return "有个签到要你亲自来一下" }
        return SignInActivityKeys.slogan
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ShinchanSceneView(height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(SignInActivityKeys.slogan)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(headline)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 4) {
                    pill("托管 \(state.autoCount)", tint: ShinColor.red)
                    pill("定时 \(state.scheduledCount)", tint: ShinColor.yellow)
                    pill("手动 \(state.manualCount)", tint: Color.white.opacity(0.45))
                    pill("AI \(state.aiCount)", tint: Color(red: 0.35, green: 0.78, blue: 0.98))
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func pill(_ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.white.opacity(0.13)))
    }
}

// MARK: - Widget

@available(iOS 16.1, *)
struct SignInActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SignInActivityAttributes.self) { context in
            PetLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(URL(string: SignInActivityKeys.openURL))

        } dynamicIsland: { context in
            island(frame: context.state.frame)
        }
    }

    /// 灵动岛内容。单独写成普通函数，避免 @ViewBuilder 里出现 `let` / `return`。
    ///
    /// 布局：左边静态「小新牵小白」，右边一颗跳动的红心。
    private func island(frame: Int) -> DynamicIsland {
        DynamicIsland {
            // 展开态：左边场景放大，右边心跳
            DynamicIslandExpandedRegion(.leading) {
                ShinchanSceneView(height: 38)
                    .padding(.leading, 2)
            }

            DynamicIslandExpandedRegion(.trailing) {
                BeatingHeartView(frame: frame, size: 20)
                    .padding(.trailing, 2)
            }

            DynamicIslandExpandedRegion(.bottom) {
                HStack(spacing: 6) {
                    Text(SignInActivityKeys.slogan)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("轻点回到 App")
                        .font(.system(size: 10))
                        .foregroundColor(ShinColor.yellow.opacity(0.9))
                }
            }
        } compactLeading: {
            // 紧凑态左侧：小新牵小白的静态场景
            ShinchanSceneView(height: 21)
        } compactTrailing: {
            // 紧凑态右侧：跳动红心
            BeatingHeartView(frame: frame, size: 16)
        } minimal: {
            // 极简态（多个活动同时存在时）：只留场景，尺寸给到能看清
            ShinchanSceneView(height: 13)
        }
        .widgetURL(URL(string: SignInActivityKeys.openURL))
        .keylineTint(ShinColor.heart)
    }
}

/// Extension 侧兜底读取 App Group 数据（活动状态异常时用于降级展示）。
@available(iOS 16.1, *)
func readSharedState() -> SignInActivityAttributes.ContentState {
    let defaults = UserDefaults(suiteName: SignInActivityKeys.appGroup)
    return SignInActivityAttributes.ContentState(
        statusText: defaults?.string(forKey: "live_status_text") ?? SignInActivityKeys.slogan,
        signedAccounts: defaults?.string(forKey: "live_signed_accounts") ?? "",
        autoCount: defaults?.integer(forKey: "live_auto_count") ?? 0,
        scheduledCount: defaults?.integer(forKey: "live_scheduled_count") ?? 0,
        manualCount: defaults?.integer(forKey: "live_manual_count") ?? 0,
        aiCount: defaults?.integer(forKey: "live_ai_count") ?? 0,
        mood: defaults?.string(forKey: "live_mood") ?? "idle",
        signedCount: defaults?.integer(forKey: "live_signed_count") ?? 0,
        frame: defaults?.integer(forKey: "live_frame") ?? 0
    )
}
