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
}
