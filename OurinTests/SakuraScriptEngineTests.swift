import Testing
@testable import Ourin

struct SakuraScriptEngineTests {
    @Test
    func parseBasics() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Hello\\n\\s[1]\\i[2,wait]\\e")
        #expect(tokens == [
            .scope(0),
            .text("Hello"),
            .newline,
            .surface(1),
            .animation(2, wait: true),
            .end
        ])
    }

    @Test
    func propertyExpand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Name %property[baseware.name]")
        #expect(tokens == [.text("Name Ourin")])
    }

    // MARK: - Escape Sequences

    @Test
    func escapedBackslash() async throws {
        let engine = SakuraScriptEngine()
        // \\ should produce a literal backslash
        let tokens = engine.parse(script: "Test\\\\Path")
        #expect(tokens == [.text("Test\\Path")])
    }

    @Test
    func escapedPercent() async throws {
        let engine = SakuraScriptEngine()
        // \% should produce a literal percent sign
        let tokens = engine.parse(script: "100\\% complete")
        #expect(tokens == [.text("100% complete")])
    }

    @Test
    func escapedBracketInArguments() async throws {
        let engine = SakuraScriptEngine()
        // \] inside brackets should produce a literal ]
        let tokens = engine.parse(script: "\\![raise,OnTest,array\\[0\\]]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["raise", "OnTest", "array[0]"])
        } else {
            Issue.record("Expected command token")
        }
    }

    @Test
    func quotedArgumentWithComma() async throws {
        let engine = SakuraScriptEngine()
        // Quoted arguments can contain commas
        let tokens = engine.parse(script: "\\![raise,OnTest,\"100,2\"]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["raise", "OnTest", "100,2"])
        } else {
            Issue.record("Expected command token")
        }
    }

    @Test
    func quotedArgumentWithDoubleQuotes() async throws {
        let engine = SakuraScriptEngine()
        // "" inside quotes should produce a literal "
        let tokens = engine.parse(script: "\\![call,ghost,\"the \"\"MobileMaster\"\"\"]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["call", "ghost", "the \"MobileMaster\""])
        } else {
            Issue.record("Expected command token")
        }
    }

    @Test
    func multipleEscapeSequences() async throws {
        let engine = SakuraScriptEngine()
        // Test multiple escape sequences in one script
        let tokens = engine.parse(script: "Path: C:\\\\Users\\\\Test\\nProgress: 50\\%")
        #expect(tokens == [
            .text("Path: C:\\Users\\Test"),
            .newline,
            .text("Progress: 50%")
        ])
    }

    // MARK: - Movement Commands

    @Test
    func moveAwayCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Moving away\\4Done")
        #expect(tokens == [
            .scope(0),
            .text("Moving away"),
            .moveAway,
            .text("Done")
        ])
    }

    @Test
    func moveCloseCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\1Moving close\\5Done")
        #expect(tokens == [
            .scope(1),
            .text("Moving close"),
            .moveClose,
            .text("Done")
        ])
    }

    // MARK: - Animation Commands

    @Test
    func animationWithWait() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\s[0]\\i[100,wait]Text after animation")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .surface(0))
        #expect(tokens[1] == .animation(100, wait: true))
        #expect(tokens[2] == .text("Text after animation"))
    }

    @Test
    func animationWithoutWait() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\i[50]Simultaneous text")
        #expect(tokens == [
            .animation(50, wait: false),
            .text("Simultaneous text")
        ])
    }

    @Test
    func animationClearCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,clear,100]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["anim", "clear", "100"])
        } else {
            Issue.record("Expected command token")
        }
    }

    @Test
    func animationPauseResumeCommands() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,pause,200]\\![anim,resume,200]")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anim", "pause", "200"])
        }
        if case .command(let name, let args) = tokens[1] {
            #expect(args == ["anim", "resume", "200"])
        }
    }

    @Test
    func animationOffsetCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,offset,300,40,50]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anim", "offset", "300", "40", "50"])
        }
    }

    @Test
    func animationAddCommands() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,add,overlay,10]\\![anim,add,base,5]")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anim", "add", "overlay", "10"])
        }
        if case .command(let name, let args) = tokens[1] {
            #expect(args == ["anim", "add", "base", "5"])
        }
    }

    // MARK: - Dressup/Bind Commands

    @Test
    func bindCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![bind,head,ribbon,1]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["bind", "head", "ribbon", "1"])
        }
    }

    @Test
    func bindCategoryCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![bind,arm,,0]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["bind", "arm", "", "0"])
        }
    }

    // MARK: - Rendering Control

    @Test
    func lockUnlockRepaint() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![lock,repaint]Hidden\\![unlock,repaint]")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["lock", "repaint"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["unlock", "repaint"])
        }
    }

    @Test
    func lockRepaintManual() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![lock,repaint,manual]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["lock", "repaint", "manual"])
        }
    }

    // MARK: - Alignment Commands

    @Test
    func alignmentOnDesktopCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,alignmentondesktop,bottom]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "alignmentondesktop", "bottom"])
        }
    }

    @Test
    func alignmentToDesktopCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,alignmenttodesktop,top]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "alignmenttodesktop", "top"])
        }
    }

    // MARK: - Scaling Commands

    @Test
    func scalingUniformCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,scaling,50]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "scaling", "50"])
        }
    }

    @Test
    func scalingNonUniformCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,scaling,50,100]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "scaling", "50", "100"])
        }
    }

    @Test
    func scalingWithTimeCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,scaling,50,100,2500]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "scaling", "50", "100", "2500"])
        }
    }

    // MARK: - Alpha/Transparency Commands

    @Test
    func alphaCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,alpha,50]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "alpha", "50"])
        }
    }

    // MARK: - Effect/Filter Commands

    @Test
    func effectCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![effect,plugin1,2.0,param]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["effect", "plugin1", "2.0", "param"])
        }
    }

    @Test
    func filterCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![filter,plugin2,1000,param]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["filter", "plugin2", "1000", "param"])
        }
    }

    // MARK: - Move Commands

    @Test
    func moveCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![move,--X=80,--Y=-400,--time=2500,--base=screen,--base-offset=left.bottom,--move-offset=left.top]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args.count == 7)
            #expect(args[0] == "move")
        }
    }

    @Test
    func moveasyncCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![moveasync,--X=-175,--Y=200,--time=5000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args[0] == "moveasync")
        }
    }

    @Test
    func moveasyncCancelCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![moveasync,cancel]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["moveasync", "cancel"])
        }
    }

    // MARK: - Position Commands

    @Test
    func setPositionCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,position,100,200,0]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "position", "100", "200", "0"])
        }
    }

    @Test
    func resetPositionCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![reset,position]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["reset", "position"])
        }
    }

    // MARK: - Z-Order Commands

    @Test
    func setZorderCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,zorder,1,0]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "zorder", "1", "0"])
        }
    }

    @Test
    func resetZorderCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![reset,zorder]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["reset", "zorder"])
        }
    }

    // MARK: - Sticky Window Commands

    @Test
    func setStickyWindowCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,sticky-window,1,0]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "sticky-window", "1", "0"])
        }
    }

    @Test
    func resetStickyWindowCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![reset,sticky-window]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["reset", "sticky-window"])
        }
    }

    // MARK: - Window Reset Command

    @Test
    func executeResetWindowPosCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![execute,resetwindowpos]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["execute", "resetwindowpos"])
        }
    }

    // MARK: - Wait Commands

    @Test
    func waitAnimationCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__w[animation,400]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__w")
            #expect(args == ["animation", "400"])
        }
    }

    // MARK: - Scope Commands

    @Test
    func scopeWithBrackets() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\p[2]Third character\\p[3]Fourth character")
        #expect(tokens == [
            .scope(2),
            .text("Third character"),
            .scope(3),
            .text("Fourth character")
        ])
    }

    @Test
    func scopeShortForm() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Sakura\\1Unyuu\\p2Third")
        #expect(tokens == [
            .scope(0),
            .text("Sakura"),
            .scope(1),
            .text("Unyuu"),
            .scope(2),
            .text("Third")
        ])
    }

    // MARK: - Complex Scenarios

    @Test
    func complexScriptWithMultipleCommands() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0\\s[0]Hello\\n\\![set,scaling,50]\\1\\s[10]\\i[2,wait]World\\e")
        #expect(tokens.count == 10)
        #expect(tokens[0] == .scope(0))
        #expect(tokens[1] == .surface(0))
        #expect(tokens[2] == .text("Hello"))
        #expect(tokens[3] == .newline)
        if case .command(let name, let args) = tokens[4] {
            #expect(args == ["set", "scaling", "50"])
        }
        #expect(tokens[5] == .scope(1))
        #expect(tokens[6] == .surface(10))
        #expect(tokens[7] == .animation(2, wait: true))
        #expect(tokens[8] == .text("World"))
        #expect(tokens[9] == .end)
    }

    // MARK: - Balloon Commands

    @Test
    func balloonIDSingleDigit() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Test\\b2Balloon 2")
        #expect(tokens == [
            .scope(0),
            .text("Test"),
            .balloon(2),
            .text("Balloon 2")
        ])
    }

    @Test
    func balloonIDBracketed() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\b[2]Large balloon")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .balloon(2))
        #expect(tokens[1] == .text("Large balloon"))
    }

    @Test
    func balloonIDNegativeOne() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\b[-1]Hidden balloon")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .balloon(-1))
        #expect(tokens[1] == .text("Hidden balloon"))
    }

    @Test
    func balloonIDWithFallback() async throws {
        let engine = SakuraScriptEngine()
        // SSP 2.6.34+ fallback syntax - parser takes first ID
        let tokens = engine.parse(script: "\\b[2,--fallback=0]Fallback test")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .balloon(2))
        #expect(tokens[1] == .text("Fallback test"))
    }

    @Test
    func balloonImageInline() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Text\\_b[test.png,inline]more text")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Text"))
        if case .command(let name, let args) = tokens[1] {
            #expect(name == "_b")
            #expect(args == ["test.png", "inline"])
        }
        #expect(tokens[2] == .text("more text"))
    }

    @Test
    func balloonImageInlineWithOptions() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_b[test.png,inline,--option=use_self_alpha]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_b")
            #expect(args == ["test.png", "inline", "--option=use_self_alpha"])
        }
    }

    @Test
    func balloonImagePositioned() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_b[image\\test.png,50,100]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_b")
            #expect(args == ["image\\test.png", "50", "100"])
        }
    }

    @Test
    func balloonImagePositionedOpaque() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_b[..\\..\\shell\\master\\surface0.png,0,15,opaque]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_b")
            #expect(args == ["..\\..\\shell\\master\\surface0.png", "0", "15", "opaque"])
        }
    }

    @Test
    func balloonImageWithClipping() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_b[test.png,10,20,--option=use_self_alpha,--clipping=100 30 150 90,--option=foreground]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_b")
            #expect(args == ["test.png", "10", "20", "--option=use_self_alpha", "--clipping=100 30 150 90", "--option=foreground"])
        }
    }

    // MARK: - Newline Variations

    @Test
    func newlineHalf() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Line 1\\n[half]Line 2")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Line 1"))
        #expect(tokens[1] == .newlineVariation("half"))
        #expect(tokens[2] == .text("Line 2"))
    }

    @Test
    func newlinePercent() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Line 1\\n[150]Line 2")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Line 1"))
        #expect(tokens[1] == .newlineVariation("150"))
        #expect(tokens[2] == .text("Line 2"))
    }

    @Test
    func newlineNegativePercent() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Line 1\\n[-250]Line 2")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Line 1"))
        #expect(tokens[1] == .newlineVariation("-250"))
        #expect(tokens[2] == .text("Line 2"))
    }

    // MARK: - Text Positioning

    @Test
    func textPositionSimple() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_l[30,100]Positioned text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_l")
            #expect(args == ["30", "100"])
        }
        #expect(tokens[1] == .text("Positioned text"))
    }

    @Test
    func textPositionWithEM() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_l[30,5em]Text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_l")
            #expect(args == ["30", "5em"])
        }
    }

    @Test
    func textPositionRelative() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_l[@-1650%,100]Text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_l")
            #expect(args == ["@-1650%", "100"])
        }
    }

    @Test
    func textPositionOmitX() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_l[,@-100]Text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_l")
            #expect(args == ["", "@-100"])
        }
    }

    // MARK: - Text Clearing

    @Test
    func textClearBasic() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\1Text\\0Text\\cAfter clear")
        #expect(tokens.count == 6)
        #expect(tokens[0] == .scope(1))
        #expect(tokens[1] == .text("Text"))
        #expect(tokens[2] == .scope(0))
        #expect(tokens[3] == .text("Text"))
        if case .command(let name, let args) = tokens[4] {
            #expect(name == "c")
            #expect(args == [])
        } else {
            Issue.record("Expected clear command")
        }
        #expect(tokens[5] == .text("After clear"))
    }

    @Test
    func textClearChars() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Delete text\\c[char,3]End")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Delete text"))
        if case .command(let name, let args) = tokens[1] {
            #expect(name == "c")
            #expect(args == ["char", "3"])
        }
        #expect(tokens[2] == .text("End"))
    }

    @Test
    func textClearCharsWithStart() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Text\\c[char,3,4]End")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[1] {
            #expect(name == "c")
            #expect(args == ["char", "3", "4"])
        }
    }

    @Test
    func textClearLines() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Line 1\\nLine 2\\c[line,1]End")
        #expect(tokens.count == 5)
        if case .command(let name, let args) = tokens[3] {
            #expect(name == "c")
            #expect(args == ["line", "1"])
        }
    }

    @Test
    func textClearLinesWithStart() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\c[line,1,2]End")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "c")
            #expect(args == ["line", "1", "2"])
        }
    }

    // MARK: - No Auto-wrap

    @Test
    func noAutoWrap() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_nNo wrap text\\_n")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_n")
            #expect(args == [])
        }
        #expect(tokens[1] == .text("No wrap text"))
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "_n")
            #expect(args == [])
        }
    }

    // MARK: - Append Mode

    @Test
    func appendMode() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\CAppend to previous")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .appendMode)
        #expect(tokens[1] == .text("Append to previous"))
    }

    // MARK: - Balloon Control Commands

    @Test
    func balloonAutoscrollDisable() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,autoscroll,disable]Locked")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["set", "autoscroll", "disable"])
        }
    }

    @Test
    func balloonAutoscrollEnable() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,autoscroll,enable]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "autoscroll", "enable"])
        }
    }

    @Test
    func balloonOffset() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonoffset,100,-50]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonoffset", "100", "-50"])
        }
    }

    @Test
    func balloonOffsetRelative() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonoffset,@100,@-50]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonoffset", "@100", "@-50"])
        }
    }

    @Test
    func balloonAlign() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonalign,top]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonalign", "top"])
        }
    }

    @Test
    func balloonMarker() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonmarker,SSTP]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonmarker", "SSTP"])
        }
    }

    @Test
    func balloonNum() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonnum,test.zip,1,5]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonnum", "test.zip", "1", "5"])
        }
    }

    @Test
    func balloonTimeout() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloontimeout,3000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloontimeout", "3000"])
        }
    }

    @Test
    func balloonWait() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,balloonwait,1.5]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "balloonwait", "1.5"])
        }
    }

    @Test
    func serikoTalk() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,serikotalk,false]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "serikotalk", "false"])
        }
    }

    @Test
    func balloonMarkerDisplay() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![*]Marker")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "!")
            #expect(args == ["*"])
        }
    }

    @Test
    func onlineMode() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![enter,onlinemode]Online\\![leave,onlinemode]")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["enter", "onlinemode"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["leave", "onlinemode"])
        }
    }

    @Test
    func nouserbreakMode() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![enter,nouserbreakmode]Text\\![leave,nouserbreakmode]")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["enter", "nouserbreakmode"])
        }
    }

    @Test
    func lockBalloonRepaint() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![lock,balloonrepaint]Hidden\\![unlock,balloonrepaint]")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["lock", "balloonrepaint"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["unlock", "balloonrepaint"])
        }
    }

    @Test
    func lockBalloonMove() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![lock,balloonmove]\\![unlock,balloonmove]")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["lock", "balloonmove"])
        }
        if case .command(let name, let args) = tokens[1] {
            #expect(args == ["unlock", "balloonmove"])
        }
    }

    // MARK: - Tag Passthrough

    @Test
    func tagPassthroughOld() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_!\\1Text\\n\\_!")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_!")
            #expect(args == [])
        }
        #expect(tokens[1] == .text("\\1Text\\n"))
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "_!")
            #expect(args == [])
        }
    }

    @Test
    func tagPassthrough() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_?\\1Text\\n\\_?")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_?")
            #expect(args == [])
        }
        #expect(tokens[1] == .text("\\1Text\\n"))
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "_?")
            #expect(args == [])
        }
    }

    // MARK: - Voice Control

    @Test
    func voiceDisable() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__v[disable]No voice\\__v")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__v")
            #expect(args == ["disable"])
        }
        #expect(tokens[1] == .text("No voice"))
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "__v")
            #expect(args == [])
        }
    }

    @Test
    func voiceAlternate() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__v[alternate,ひらがな]Text\\__v")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__v")
            #expect(args == ["alternate", "ひらがな"])
        }
    }

    // MARK: - Font Commands

    @Test
    func fontAlign() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[align,center]Center\\n\\f[align,right]Right")
        #expect(tokens.count == 5)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "f")
            #expect(args == ["align", "center"])
        }
        #expect(tokens[1] == .text("Center"))
        #expect(tokens[2] == .newline)
        if case .command(let name, let args) = tokens[3] {
            #expect(name == "f")
            #expect(args == ["align", "right"])
        }
    }

    @Test
    func fontValign() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[valign,bottom]Bottom text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "f")
            #expect(args == ["valign", "bottom"])
        }
    }

    @Test
    func fontName() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[name,メイリオ,meiryo.ttf]Text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "f")
            #expect(args == ["name", "メイリオ", "meiryo.ttf"])
        }
    }

    @Test
    func fontHeight() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[height,15]Size 15\\f[height,+3]Bigger\\f[height,200%]Double")
        #expect(tokens.count == 6)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["height", "15"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["height", "+3"])
        }
        if case .command(let name, let args) = tokens[4] {
            #expect(args == ["height", "200%"])
        }
    }

    @Test
    func fontColor() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[color,red]Red\\f[color,100,150,200]RGB")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["color", "red"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["color", "100", "150", "200"])
        }
    }

    @Test
    func fontShadowColor() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[shadowcolor,#ffff00]Yellow shadow\\f[shadowcolor,none]No shadow")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["shadowcolor", "#ffff00"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["shadowcolor", "none"])
        }
    }

    @Test
    func fontShadowStyle() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[shadowstyle,outline]Outlined")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["shadowstyle", "outline"])
        }
    }

    @Test
    func fontOutline() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[outline,1]Outlined\\f[outline,default]Normal")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["outline", "1"])
        }
        if case .command(let name, let args) = tokens[2] {
            #expect(args == ["outline", "default"])
        }
    }

    @Test
    func fontAnchorColor() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchor.font.color,50%,90%,20%]Anchor")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchor.font.color", "50%", "90%", "20%"])
        }
    }

    @Test
    func fontBold() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[bold,1]Bold\\f[bold,default]Normal")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["bold", "1"])
        }
    }

    @Test
    func fontItalic() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[italic,1]Italic\\f[italic,0]Normal")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["italic", "1"])
        }
    }

    @Test
    func fontStrike() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[strike,1]Strike\\f[strike,false]Normal")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["strike", "1"])
        }
    }

    @Test
    func fontUnderline() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[underline,true]Underlined\\f[underline,0]Normal")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["underline", "true"])
        }
    }

    @Test
    func fontSub() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "H\\f[sub,1]2\\f[sub,0]O")
        #expect(tokens.count == 5)
        if case .command(let name, let args) = tokens[1] {
            #expect(args == ["sub", "1"])
        }
    }

    @Test
    func fontSup() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "X\\f[sup,1]2\\f[sup,default]")
        #expect(tokens.count == 4)
        if case .command(let name, let args) = tokens[1] {
            #expect(args == ["sup", "1"])
        }
    }

    @Test
    func fontDefault() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[bold,1]\\f[height,20]Text\\f[default]Reset")
        #expect(tokens.count == 5)
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "f")
            #expect(args == ["default"])
        }
    }

    @Test
    func fontDisable() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[disable]Disabled text")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["disable"])
        }
    }

    @Test
    func fontComplexCombination() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[shadowcolor,#6699cc]\\f[bold,1]\\f[underline,1]\\f[height,20]Styled\\f[default]Normal")
        #expect(tokens.count == 7)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["shadowcolor", "#6699cc"])
        }
        if case .command(let name, let args) = tokens[5] {
            #expect(args == ["default"])
        }
    }

    // MARK: - Wait Commands

    @Test
    func waitClickCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Text\\tMore text")
        #expect(tokens.count == 4)
        #expect(tokens[0] == .scope(0))
        #expect(tokens[1] == .text("Text"))
        #expect(tokens[2] == .wait)
        #expect(tokens[3] == .text("More text"))
    }

    @Test
    func waitNumericCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\w5")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "w")
            #expect(args == ["5"])
        }
    }

    @Test
    func waitBracketCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_w[1000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_w")
            #expect(args == ["1000"])
        }
    }

    @Test
    func waitDoubleUnderscoreCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__w[500]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__w")
            #expect(args == ["500"])
        }
    }

    // MARK: - End Conversation Commands

    @Test
    func endConversationBasic() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Done\\x")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .scope(0))
        #expect(tokens[1] == .text("Done"))
        #expect(tokens[2] == .endConversation(clearBalloon: true))
    }

    @Test
    func endConversationNoClear() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Done\\x[noclear]")
        #expect(tokens.count == 3)
        #expect(tokens[2] == .endConversation(clearBalloon: false))
    }

    // MARK: - Choice Commands

    @Test
    func choiceCancelCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\q[Yes,OnYes]\\q[No,OnNo]\\z")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "q")
            #expect(args == ["Yes", "OnYes"])
        }
        #expect(tokens[2] == .choiceCancel)
    }

    @Test
    func choiceMarkerCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\*Choice text")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .choiceMarker)
        #expect(tokens[1] == .text("Choice text"))
    }

    @Test
    func anchorMarkerCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\aLink text")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .anchor)
        #expect(tokens[1] == .text("Link text"))
    }

    @Test
    func choiceLineBrCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Line 1\\-Line 2")
        #expect(tokens.count == 3)
        #expect(tokens[0] == .text("Line 1"))
        #expect(tokens[1] == .choiceLineBr)
        #expect(tokens[2] == .text("Line 2"))
    }

    @Test
    func choiceIDTitleFormat() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\q[OnTest][Test Choice]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "q")
            #expect(args == ["OnTest", "Test Choice"])
        }
    }

    @Test
    func choiceScriptFormat() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\q[Execute,script:\\![raise,OnTest]]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "q")
            #expect(args.count == 2)
            #expect(args[0] == "Execute")
            #expect(args[1] == "script:\\![raise,OnTest]")
        }
    }

    @Test
    func anchorCommandWithArgs() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_a[OnClick]Link\\_a")
        #expect(tokens.count == 3)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_a")
            #expect(args == ["OnClick"])
        }
        #expect(tokens[1] == .text("Link"))
        if case .command(let name, let args) = tokens[2] {
            #expect(name == "_a")
            #expect(args == [])
        }
    }

    @Test
    func anchorWithReferences() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_a[OnTest,r0,r1]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_a")
            #expect(args == ["OnTest", "r0", "r1"])
        }
    }

    @Test
    func quickSectionMarker() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_qQuick section")
        #expect(tokens.count == 2)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_q")
            #expect(args == [])
        }
    }

    @Test
    func choiceTimeoutCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,choicetimeout,5000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "choicetimeout", "5000"])
        }
    }

    @Test
    func choiceQueueCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__q[OnTest,OnTest2]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__q")
            #expect(args == ["OnTest", "OnTest2"])
        }
    }

    // MARK: - Event/Boot Commands

    @Test
    func bootGhostCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\+Boot ghost")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .bootGhost)
        #expect(tokens[1] == .text("Boot ghost"))
    }

    @Test
    func bootAllGhostsCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_+Boot all")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .bootAllGhosts)
        #expect(tokens[1] == .text("Boot all"))
    }

    @Test
    func openPreferencesCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\vPreferences")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .openPreferences)
        #expect(tokens[1] == .text("Preferences"))
    }

    @Test
    func openURLCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\6URL")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .openURL)
        #expect(tokens[1] == .text("URL"))
    }

    @Test
    func openEmailCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\7Email")
        #expect(tokens.count == 2)
        #expect(tokens[0] == .openEmail)
        #expect(tokens[1] == .text("Email"))
    }

    @Test
    func changeGhostCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![change,ghost,emily]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["change", "ghost", "emily"])
        }
    }

    @Test
    func changeShellCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![change,shell,master]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["change", "shell", "master"])
        }
    }

    @Test
    func changeBalloonCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![change,balloon,SSP]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["change", "balloon", "SSP"])
        }
    }

    @Test
    func callGhostCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![call,ghost,emily]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["call", "ghost", "emily"])
        }
    }

    // MARK: - Sound Commands

    @Test
    func playSoundCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\8[sound.wav]")
        #expect(tokens.count == 1)
        #expect(tokens[0] == .playSound("sound.wav"))
    }

    @Test
    func playSoundWithPath() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\8[sound\\effect.mp3]")
        #expect(tokens.count == 1)
        #expect(tokens[0] == .playSound("sound\\effect.mp3"))
    }

    @Test
    func voiceFileCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_v[voice.wav]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_v")
            #expect(args == ["voice.wav"])
        }
    }

    @Test
    func voiceStopCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_V")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_V")
            #expect(args == [])
        }
    }

    // MARK: - Advanced Event Commands

    @Test
    func updateBymyselfCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![updatebymyself]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["updatebymyself"])
        }
    }

    @Test
    func updatePlatformCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![update,platform]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["update", "platform"])
        }
    }

    @Test
    func updateOtherCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![updateother]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["updateother"])
        }
    }

    @Test
    func executeSntpCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![executesntp]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["executesntp"])
        }
    }

    @Test
    func executeHeadlineCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![execute,headline,RSS Feed]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["execute", "headline", "RSS Feed"])
        }
    }

    @Test
    func biffCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![biff]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["biff"])
        }
    }

    @Test
    func vanishBymyselfCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![vanishbymyself]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["vanishbymyself"])
        }
    }

    @Test
    func raiseEventCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![raise,OnTest,value1,value2]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["raise", "OnTest", "value1", "value2"])
        }
    }

    @Test
    func embedEventCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![embed,OnTest,arg0,arg1]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["embed", "OnTest", "arg0", "arg1"])
        }
    }

    @Test
    func timerRaiseCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![timerraise,5000,1,OnTimer]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["timerraise", "5000", "1", "OnTimer"])
        }
    }

    @Test
    func raiseOtherCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![raiseother,emily,OnTest]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["raiseother", "emily", "OnTest"])
        }
    }

    @Test
    func notifyCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![notify,OnNotify]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["notify", "OnNotify"])
        }
    }

    @Test
    func notifyOtherCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![notifyother,emily,OnNotify]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["notifyother", "emily", "OnNotify"])
        }
    }

    @Test
    func raisePluginCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![raiseplugin,MyPlugin,OnEvent]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["raiseplugin", "MyPlugin", "OnEvent"])
        }
    }

    // MARK: - Window State Commands

    @Test
    func setWindowStateStayOnTop() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,windowstate,stayontop]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "windowstate", "stayontop"])
        }
    }

    @Test
    func setWindowStateNotStayOnTop() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,windowstate,!stayontop]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "windowstate", "!stayontop"])
        }
    }

    @Test
    func setWindowStateMinimize() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,windowstate,minimize]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "windowstate", "minimize"])
        }
    }

    @Test
    func setWallpaperCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,wallpaper,image.jpg,center]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "wallpaper", "image.jpg", "center"])
        }
    }

    @Test
    func setTasktrayIconCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,tasktrayicon,icon.ico,tooltip]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "tasktrayicon", "icon.ico", "tooltip"])
        }
    }

    @Test
    func setTrayBalloonCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,trayballoon,title=Test,text=Message]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "trayballoon", "title=Test", "text=Message"])
        }
    }

    @Test
    func setOtherGhostTalkCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,otherghosttalk,true]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "otherghosttalk", "true"])
        }
    }

    @Test
    func setOtherSurfaceChangeCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![set,othersurfacechange,false]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["set", "othersurfacechange", "false"])
        }
    }

    // MARK: - Synchronization Commands

    @Test
    func syncCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_s")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_s")
            #expect(args == [])
        }
    }

    @Test
    func syncWithIDsCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\_s[100,200,300]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "_s")
            #expect(args == ["100", "200", "300"])
        }
    }

    @Test
    func waitSyncObjectCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![wait,syncobject,myobject,5000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["wait", "syncobject", "myobject", "5000"])
        }
    }

    @Test
    func quickSectionTrueCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![quicksection,true]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["quicksection", "true"])
        }
    }

    @Test
    func quickSectionFalseCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![quicksection,false]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["quicksection", "false"])
        }
    }

    // MARK: - Animation Control Commands

    @Test
    func animStopCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,stop]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anim", "stop"])
        }
    }

    @Test
    func animAddTextCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![anim,add,text,100,200,500,50,Hello,1000,255,0,0,20,Arial]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anim", "add", "text", "100", "200", "500", "50", "Hello", "1000", "255", "0", "0", "20", "Arial"])
        }
    }

    @Test
    func effect2Command() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![effect2,100,plugin,1.5,param]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["effect2", "100", "plugin", "1.5", "param"])
        }
    }

    @Test
    func filterClearCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![filter]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["filter"])
        }
    }

    // MARK: - Choice Marker Style Commands

    @Test
    func cursorStyleCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursorstyle,underline]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "f")
            #expect(args == ["cursorstyle", "underline"])
        }
    }

    @Test
    func cursorColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursorcolor,255,0,0]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["cursorcolor", "255", "0", "0"])
        }
    }

    @Test
    func cursorBrushColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursorbrushcolor,#ff0000]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["cursorbrushcolor", "#ff0000"])
        }
    }

    @Test
    func cursorPenColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursorpencolor,blue]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["cursorpencolor", "blue"])
        }
    }

    @Test
    func cursorFontColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursorfontcolor,128,128,255]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["cursorfontcolor", "128", "128", "255"])
        }
    }

    @Test
    func cursorMethodCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[cursormethod,base]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["cursormethod", "base"])
        }
    }

    @Test
    func anchorStyleCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchorstyle,none]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchorstyle", "none"])
        }
    }

    @Test
    func anchorColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchorcolor,0,0,255]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchorcolor", "0", "0", "255"])
        }
    }

    @Test
    func anchorVisitedStyleCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchorvisitedstyle,strike]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchorvisitedstyle", "strike"])
        }
    }

    @Test
    func anchorVisitedColorCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchorvisitedcolor,128,0,128]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchorvisitedcolor", "128", "0", "128"])
        }
    }

    @Test
    func anchorNotSelectStyleCommand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\f[anchornotselectstyle,line]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(args == ["anchornotselectstyle", "line"])
        }
    }

    // MARK: - Comprehensive Integration Tests

    @Test
    func complexScriptWithNewCommands() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\0\\s[0]Hello\\t\\8[sound.wav]\\nPress to continue\\x"
        let tokens = engine.parse(script: script)
        
        #expect(tokens.count == 8)
        #expect(tokens[0] == .scope(0))
        #expect(tokens[1] == .surface(0))
        #expect(tokens[2] == .text("Hello"))
        #expect(tokens[3] == .wait)
        #expect(tokens[4] == .playSound("sound.wav"))
        #expect(tokens[5] == .newline)
        #expect(tokens[6] == .text("Press to continue"))
        #expect(tokens[7] == .endConversation(clearBalloon: true))
    }

    @Test
    func choiceDialogWithAllFeatures() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\0Choose:\\n\\q[Yes,OnYes]\\q[No,OnNo]\\z"
        let tokens = engine.parse(script: script)
        
        #expect(tokens.count == 6)
        #expect(tokens[0] == .scope(0))
        #expect(tokens[1] == .text("Choose:"))
        #expect(tokens[2] == .newline)
        if case .command(let name, let args) = tokens[3] {
            #expect(name == "q")
            #expect(args == ["Yes", "OnYes"])
        }
        if case .command(let name, let args) = tokens[4] {
            #expect(name == "q")
            #expect(args == ["No", "OnNo"])
        }
        #expect(tokens[5] == .choiceCancel)
    }

    @Test
    func eventCommandSequence() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\0Opening URL\\6\\nOpening Email\\7\\nBooting ghost\\+"
        let tokens = engine.parse(script: script)
        
        var foundOpenURL = false
        var foundOpenEmail = false
        var foundBootGhost = false
        
        for token in tokens {
            if token == .openURL { foundOpenURL = true }
            if token == .openEmail { foundOpenEmail = true }
            if token == .bootGhost { foundBootGhost = true }
        }
        
        #expect(foundOpenURL)
        #expect(foundOpenEmail)
        #expect(foundBootGhost)
    }

    @Test
    func multiScopeConversation() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\0\\s[0]Sakura speaks\\t\\1\\s[10]Unyuu replies\\t\\p[2]Third character\\x[noclear]"
        let tokens = engine.parse(script: script)
        
        // Verify we have the expected scopes
        var scopes: [Int] = []
        for token in tokens {
            if case .scope(let id) = token {
                scopes.append(id)
            }
        }
        #expect(scopes == [0, 1, 2])
        
        // Verify end conversation without clear
        if case .endConversation(let clearBalloon) = tokens.last! {
            #expect(clearBalloon == false)
        }
    }

    @Test
    func fontStylingWithChoices() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\f[bold,1]\\f[color,red]Bold Red\\f[default]\\nNormal\\n\\q[Continue,OnContinue]"
        let tokens = engine.parse(script: script)
        
        #expect(tokens.count == 7)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "f")
            #expect(args == ["bold", "1"])
        }
        if case .command(let name, let args) = tokens[1] {
            #expect(name == "f")
            #expect(args == ["color", "red"])
        }
    }

    @Test
    func soundAndAnimationSequence() async throws {
        let engine = SakuraScriptEngine()
        let script = "\\8[bgm.mp3]\\i[100,wait]\\s[5]Animation done"
        let tokens = engine.parse(script: script)
        
        #expect(tokens[0] == .playSound("bgm.mp3"))
        #expect(tokens[1] == .animation(100, wait: true))
        #expect(tokens[2] == .surface(5))
        #expect(tokens[3] == .text("Animation done"))
    }

    @Test
    func allNewTokenTypesInOneScript() async throws {
        let engine = SakuraScriptEngine()
        // Test a script that uses all new token types
        let script = "\\0Start\\t\\8[s.wav]\\*Choice\\a\\-Break\\+\\z\\6\\7\\v\\_+\\x"
        let tokens = engine.parse(script: script)
        
        // Verify all new token types are present
        var foundWait = false
        var foundPlaySound = false
        var foundChoiceMarker = false
        var foundAnchor = false
        var foundChoiceLineBr = false
        var foundBootGhost = false
        var foundChoiceCancel = false
        var foundOpenURL = false
        var foundOpenEmail = false
        var foundOpenPreferences = false
        var foundBootAllGhosts = false
        var foundEndConversation = false
        
        for token in tokens {
            if token == .wait { foundWait = true }
            if case .playSound(_) = token { foundPlaySound = true }
            if token == .choiceMarker { foundChoiceMarker = true }
            if token == .anchor { foundAnchor = true }
            if token == .choiceLineBr { foundChoiceLineBr = true }
            if token == .bootGhost { foundBootGhost = true }
            if token == .choiceCancel { foundChoiceCancel = true }
            if token == .openURL { foundOpenURL = true }
            if token == .openEmail { foundOpenEmail = true }
            if token == .openPreferences { foundOpenPreferences = true }
            if token == .bootAllGhosts { foundBootAllGhosts = true }
            if case .endConversation(_) = token { foundEndConversation = true }
        }
        
        #expect(foundWait)
        #expect(foundPlaySound)
        #expect(foundChoiceMarker)
        #expect(foundAnchor)
        #expect(foundChoiceLineBr)
        #expect(foundBootGhost)
        #expect(foundChoiceCancel)
        #expect(foundOpenURL)
        #expect(foundOpenEmail)
        #expect(foundOpenPreferences)
        #expect(foundBootAllGhosts)
        #expect(foundEndConversation)
    }
}
