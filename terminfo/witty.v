// Witty's terminfo entry.
//
// Translated from ghostty/src/terminfo/ghostty.zig. The capability list and its
// commentary are carried over verbatim and in source order.
module terminfo

// witty is Witty's terminfo entry.
pub const witty = Source{
	names: [
		'xterm-witty',
		'witty',
		'Witty',
	]
	capabilities: [
		// automatic right margin -- when reaching the end of a line, text is
		// wrapped to the next line.
		Capability{ name: 'am', value: CapabilityValueBoolean{} },

		// background color erase -- screen is erased with the background color
		Capability{ name: 'bce', value: CapabilityValueBoolean{} },

		// terminal can change color definitions, i.e. we can change the color
		// palette.
		Capability{ name: 'ccc', value: CapabilityValueBoolean{} },

		// supports changing the window title.
		Capability{ name: 'hs', value: CapabilityValueBoolean{} },

		// terminal has a meta key
		Capability{ name: 'km', value: CapabilityValueBoolean{} },

		// terminal will not echo input on the screen on its own
		Capability{ name: 'mc5i', value: CapabilityValueBoolean{} },

		// safe to move (move what?) while in insert/standout mode. (???)
		Capability{ name: 'mir', value: CapabilityValueBoolean{} },
		Capability{ name: 'msgr', value: CapabilityValueBoolean{} },

		// no pad character (???)
		Capability{ name: 'npc', value: CapabilityValueBoolean{} },

		// newline ignored after 80 cols (???)
		Capability{ name: 'xenl', value: CapabilityValueBoolean{} },

		// Terminal supports default colors
		Capability{ name: 'AX', value: CapabilityValueBoolean{} },

		// Tmux "truecolor" mode. Other programs also use this to detect
		// if the terminal supports "truecolor". This means that the terminal
		// can display 24-bit RGB colors.
		Capability{ name: 'Tc', value: CapabilityValueBoolean{} },

		// Colored underlines. https://sw.kovidgoyal.net/kitty/underlines/
		Capability{ name: 'Su', value: CapabilityValueBoolean{} },

		// Terminal supports a number of xterm extensions
		Capability{ name: 'XT', value: CapabilityValueBoolean{} },

		// Full keyboard support using Kitty's keyboard protocol:
		// https://sw.kovidgoyal.net/kitty/keyboard-protocol/
		Capability{ name: 'fullkbd', value: CapabilityValueBoolean{} },

		// Number of colors in the color palette.
		Capability{ name: 'colors', value: CapabilityValueNumeric{ value: 256 } },

		// Number of columns in a line. Our terminal is variable width on
		// Window resize but this appears to just be the value set by most
		// terminals.
		Capability{ name: 'cols', value: CapabilityValueNumeric{ value: 80 } },

		// Initial tabstop interval.
		Capability{ name: 'it', value: CapabilityValueNumeric{ value: 8 } },

		// Number of lines on a page. Similar to cols this is variable width
		// but this appears to be the value set by most terminals.
		Capability{ name: 'lines', value: CapabilityValueNumeric{ value: 24 } },

		// Number of color pairs on the screen.
		Capability{ name: 'pairs', value: CapabilityValueNumeric{ value: 32767 } },

		// Alternate character set. This is the VT100 alternate character set.
		// I don't know what the value means, I copied this from Kitty and
		// verified with some other terminals (looks similar).
		Capability{ name: 'acsc', value: CapabilityValueString{ value: '++\\,\\,--..00``aaffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~' } },

		// Curly, dashed, etc underlines
		Capability{ name: 'Smulx', value: CapabilityValueString{ value: '\\E[4:%p1%dm' } },

		// Colored underlines
		Capability{ name: 'Setulc', value: CapabilityValueString{ value: '\\E[58:2::%p1%{65536}%/%d:%p1%{256}%/%{255}%&%d:%p1%{255}%&%d%;m' } },

		// Cursor styles
		Capability{ name: 'Ss', value: CapabilityValueString{ value: '\\E[%p1%d q' } },

		// Cursor style reset
		Capability{ name: 'Se', value: CapabilityValueString{ value: '\\E[2 q' } },

		// OSC 52 Clipboard
		Capability{ name: 'Ms', value: CapabilityValueString{ value: '\\E]52;%p1%s;%p2%s\\007' } },

		// Synchronized output
		Capability{ name: 'Sync', value: CapabilityValueString{ value: '\\E[?2026%?%p1%{1}%-%tl%eh%;' } },

		// Bracketed paste mode
		Capability{ name: 'BD', value: CapabilityValueString{ value: '\\E[?2004l' } },
		Capability{ name: 'BE', value: CapabilityValueString{ value: '\\E[?2004h' } },
		// Bracketed paste start/end
		Capability{ name: 'PS', value: CapabilityValueString{ value: '\\E[200~' } },
		Capability{ name: 'PE', value: CapabilityValueString{ value: '\\E[201~' } },

		// Mouse
		Capability{ name: 'XM', value: CapabilityValueString{ value: '\\E[?1006;1000%?%p1%{1}%=%th%el%;' } },
		Capability{ name: 'xm', value: CapabilityValueString{ value: '\\E[<%i%p3%d;%p1%d;%p2%d;%?%p4%tM%em%;' } },

		// Secondary device attributes request / response
		Capability{ name: 'RV', value: CapabilityValueString{ value: '\\E[>c' } },
		Capability{ name: 'rv', value: CapabilityValueString{ value: '\\E\\\\[[0-9]+;[0-9]+;[0-9]+c' } },

		// XTVERSION
		Capability{ name: 'XR', value: CapabilityValueString{ value: '\\E[>0q' } },
		Capability{ name: 'xr', value: CapabilityValueString{ value: '\\EP>\\\\|[ -~]+a\\E\\\\' } },

		// DECSLRM (Left/Right Margins)
		Capability{ name: 'Enmg', value: CapabilityValueString{ value: '\\E[?69h' } },
		Capability{ name: 'Dsmg', value: CapabilityValueString{ value: '\\E[?69l' } },
		Capability{ name: 'Clmg', value: CapabilityValueString{ value: '\\E[s' } },
		Capability{ name: 'Cmg', value: CapabilityValueString{ value: '\\E[%i%p1%d;%p2%ds' } },

		// Clear screen. E3 is the extension to clear scrollback
		Capability{ name: 'clear', value: CapabilityValueString{ value: '\\E[H\\E[2J' } },
		Capability{ name: 'E3', value: CapabilityValueString{ value: '\\E[3J' } },

		// Focus reporting. Introduced in ncurses 6.4-20231028
		Capability{ name: 'fe', value: CapabilityValueString{ value: '\\E[?1004h' } },
		Capability{ name: 'fd', value: CapabilityValueString{ value: '\\E[?1004l' } },
		Capability{ name: 'kxIN', value: CapabilityValueString{ value: '\\E[I' } },
		Capability{ name: 'kxOUT', value: CapabilityValueString{ value: '\\E[O' } },

		// These are all capabilities that should be pretty straightforward
		// and map to input sequences.
		Capability{ name: 'bel', value: CapabilityValueString{ value: '^G' } },
		Capability{ name: 'blink', value: CapabilityValueString{ value: '\\E[5m' } },
		Capability{ name: 'bold', value: CapabilityValueString{ value: '\\E[1m' } },
		Capability{ name: 'cbt', value: CapabilityValueString{ value: '\\E[Z' } },
		Capability{ name: 'civis', value: CapabilityValueString{ value: '\\E[?25l' } },
		Capability{ name: 'cnorm', value: CapabilityValueString{ value: '\\E[?12l\\E[?25h' } },
		Capability{ name: 'cr', value: CapabilityValueString{ value: '\\r' } },
		Capability{ name: 'csr', value: CapabilityValueString{ value: '\\E[%i%p1%d;%p2%dr' } },
		Capability{ name: 'cub', value: CapabilityValueString{ value: '\\E[%p1%dD' } },
		Capability{ name: 'cub1', value: CapabilityValueString{ value: '^H' } },
		Capability{ name: 'cud', value: CapabilityValueString{ value: '\\E[%p1%dB' } },
		Capability{ name: 'cud1', value: CapabilityValueString{ value: '^J' } },
		Capability{ name: 'cuf', value: CapabilityValueString{ value: '\\E[%p1%dC' } },
		Capability{ name: 'cuf1', value: CapabilityValueString{ value: '\\E[C' } },
		Capability{ name: 'cup', value: CapabilityValueString{ value: '\\E[%i%p1%d;%p2%dH' } },
		Capability{ name: 'cuu', value: CapabilityValueString{ value: '\\E[%p1%dA' } },
		Capability{ name: 'cuu1', value: CapabilityValueString{ value: '\\E[A' } },
		Capability{ name: 'cvvis', value: CapabilityValueString{ value: '\\E[?12;25h' } },
		Capability{ name: 'dch', value: CapabilityValueString{ value: '\\E[%p1%dP' } },
		Capability{ name: 'dch1', value: CapabilityValueString{ value: '\\E[P' } },
		Capability{ name: 'dim', value: CapabilityValueString{ value: '\\E[2m' } },
		Capability{ name: 'dl', value: CapabilityValueString{ value: '\\E[%p1%dM' } },
		Capability{ name: 'dl1', value: CapabilityValueString{ value: '\\E[M' } },
		Capability{ name: 'dsl', value: CapabilityValueString{ value: '\\E]2;\\007' } },
		Capability{ name: 'ech', value: CapabilityValueString{ value: '\\E[%p1%dX' } },
		Capability{ name: 'ed', value: CapabilityValueString{ value: '\\E[J' } },
		Capability{ name: 'el', value: CapabilityValueString{ value: '\\E[K' } },
		Capability{ name: 'el1', value: CapabilityValueString{ value: '\\E[1K' } },
		Capability{ name: 'flash', value: CapabilityValueString{ value: '\\E[?5h$<100/>\\E[?5l' } },
		Capability{ name: 'fsl', value: CapabilityValueString{ value: '^G' } },
		Capability{ name: 'home', value: CapabilityValueString{ value: '\\E[H' } },
		Capability{ name: 'hpa', value: CapabilityValueString{ value: '\\E[%i%p1%dG' } },
		Capability{ name: 'ht', value: CapabilityValueString{ value: '^I' } },
		Capability{ name: 'hts', value: CapabilityValueString{ value: '\\EH' } },
		Capability{ name: 'ich', value: CapabilityValueString{ value: '\\E[%p1%d@' } },
		Capability{ name: 'ich1', value: CapabilityValueString{ value: '\\E[@' } },
		Capability{ name: 'il', value: CapabilityValueString{ value: '\\E[%p1%dL' } },
		Capability{ name: 'il1', value: CapabilityValueString{ value: '\\E[L' } },
		Capability{ name: 'ind', value: CapabilityValueString{ value: '\\n' } },
		Capability{ name: 'indn', value: CapabilityValueString{ value: '\\E[%p1%dS' } },
		Capability{ name: 'initc', value: CapabilityValueString{ value: '\\E]4;%p1%d;rgb\\:%p2%{255}%*%{1000}%/%2.2X/%p3%{255}%*%{1000}%/%2.2X/%p4%{255}%*%{1000}%/%2.2X\\E\\\\' } },
		Capability{ name: 'invis', value: CapabilityValueString{ value: '\\E[8m' } },
		Capability{ name: 'oc', value: CapabilityValueString{ value: '\\E]104\\007' } },
		Capability{ name: 'op', value: CapabilityValueString{ value: '\\E[39;49m' } },
		Capability{ name: 'rc', value: CapabilityValueString{ value: '\\E8' } },
		Capability{ name: 'rep', value: CapabilityValueString{ value: '%p1%c\\E[%p2%{1}%-%db' } },
		Capability{ name: 'rev', value: CapabilityValueString{ value: '\\E[7m' } },
		Capability{ name: 'ri', value: CapabilityValueString{ value: '\\EM' } },
		Capability{ name: 'rin', value: CapabilityValueString{ value: '\\E[%p1%dT' } },
		Capability{ name: 'ritm', value: CapabilityValueString{ value: '\\E[23m' } },
		Capability{ name: 'rmacs', value: CapabilityValueString{ value: '\\E(B' } },
		Capability{ name: 'rmam', value: CapabilityValueString{ value: '\\E[?7l' } },
		Capability{ name: 'rmcup', value: CapabilityValueString{ value: '\\E[?1049l' } },
		Capability{ name: 'rmir', value: CapabilityValueString{ value: '\\E[4l' } },
		Capability{ name: 'rmkx', value: CapabilityValueString{ value: '\\E[?1l\\E>' } },
		Capability{ name: 'rmso', value: CapabilityValueString{ value: '\\E[27m' } },
		Capability{ name: 'rmul', value: CapabilityValueString{ value: '\\E[24m' } },
		Capability{ name: 'rmxx', value: CapabilityValueString{ value: '\\E[29m' } },
		Capability{ name: 'setab', value: CapabilityValueString{ value: '\\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m' } },
		Capability{ name: 'setaf', value: CapabilityValueString{ value: '\\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m' } },
		Capability{ name: 'setrgbb', value: CapabilityValueString{ value: '\\E[48:2:%p1%d:%p2%d:%p3%dm' } },
		Capability{ name: 'setrgbf', value: CapabilityValueString{ value: '\\E[38:2:%p1%d:%p2%d:%p3%dm' } },
		Capability{ name: 'sgr', value: CapabilityValueString{ value: '%?%p9%t\\E(0%e\\E(B%;\\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;%?%p7%t;8%;m' } },
		Capability{ name: 'sgr0', value: CapabilityValueString{ value: '\\E(B\\E[m' } },
		Capability{ name: 'sitm', value: CapabilityValueString{ value: '\\E[3m' } },
		Capability{ name: 'smacs', value: CapabilityValueString{ value: '\\E(0' } },
		Capability{ name: 'smam', value: CapabilityValueString{ value: '\\E[?7h' } },
		Capability{ name: 'smcup', value: CapabilityValueString{ value: '\\E[?1049h' } },
		Capability{ name: 'smir', value: CapabilityValueString{ value: '\\E[4h' } },
		Capability{ name: 'smkx', value: CapabilityValueString{ value: '\\E[?1h\\E=' } },
		Capability{ name: 'smso', value: CapabilityValueString{ value: '\\E[7m' } },
		Capability{ name: 'smul', value: CapabilityValueString{ value: '\\E[4m' } },
		Capability{ name: 'smxx', value: CapabilityValueString{ value: '\\E[9m' } },
		Capability{ name: 'tbc', value: CapabilityValueString{ value: '\\E[3g' } },
		Capability{ name: 'tsl', value: CapabilityValueString{ value: '\\E]2;' } },
		Capability{ name: 'u6', value: CapabilityValueString{ value: '\\E[%i%d;%dR' } },
		Capability{ name: 'u7', value: CapabilityValueString{ value: '\\E[6n' } },
		Capability{ name: 'u8', value: CapabilityValueString{ value: '\\E[?%[;0123456789]c' } },
		Capability{ name: 'u9', value: CapabilityValueString{ value: '\\E[c' } },
		Capability{ name: 'vpa', value: CapabilityValueString{ value: '\\E[%i%p1%dd' } },

		//-----------------------------------------------------------
		// Completely unvalidated entries that are blindly copied from
		// other terminals (Kitty, Wezterm, Alacritty) and may or may not
		// actually work with Ghostty. todo is to validate these!

		Capability{ name: 'kDC', value: CapabilityValueString{ value: '\\E[3;2~' } },
		Capability{ name: 'kDC3', value: CapabilityValueString{ value: '\\E[3;3~' } },
		Capability{ name: 'kDC4', value: CapabilityValueString{ value: '\\E[3;4~' } },
		Capability{ name: 'kDC5', value: CapabilityValueString{ value: '\\E[3;5~' } },
		Capability{ name: 'kDC6', value: CapabilityValueString{ value: '\\E[3;6~' } },
		Capability{ name: 'kDC7', value: CapabilityValueString{ value: '\\E[3;7~' } },
		Capability{ name: 'kDN', value: CapabilityValueString{ value: '\\E[1;2B' } },
		Capability{ name: 'kDN3', value: CapabilityValueString{ value: '\\E[1;3B' } },
		Capability{ name: 'kDN4', value: CapabilityValueString{ value: '\\E[1;4B' } },
		Capability{ name: 'kDN5', value: CapabilityValueString{ value: '\\E[1;5B' } },
		Capability{ name: 'kDN6', value: CapabilityValueString{ value: '\\E[1;6B' } },
		Capability{ name: 'kDN7', value: CapabilityValueString{ value: '\\E[1;7B' } },
		Capability{ name: 'kEND', value: CapabilityValueString{ value: '\\E[1;2F' } },
		Capability{ name: 'kEND3', value: CapabilityValueString{ value: '\\E[1;3F' } },
		Capability{ name: 'kEND4', value: CapabilityValueString{ value: '\\E[1;4F' } },
		Capability{ name: 'kEND5', value: CapabilityValueString{ value: '\\E[1;5F' } },
		Capability{ name: 'kEND6', value: CapabilityValueString{ value: '\\E[1;6F' } },
		Capability{ name: 'kEND7', value: CapabilityValueString{ value: '\\E[1;7F' } },
		Capability{ name: 'kHOM', value: CapabilityValueString{ value: '\\E[1;2H' } },
		Capability{ name: 'kHOM3', value: CapabilityValueString{ value: '\\E[1;3H' } },
		Capability{ name: 'kHOM4', value: CapabilityValueString{ value: '\\E[1;4H' } },
		Capability{ name: 'kHOM5', value: CapabilityValueString{ value: '\\E[1;5H' } },
		Capability{ name: 'kHOM6', value: CapabilityValueString{ value: '\\E[1;6H' } },
		Capability{ name: 'kHOM7', value: CapabilityValueString{ value: '\\E[1;7H' } },
		Capability{ name: 'kIC', value: CapabilityValueString{ value: '\\E[2;2~' } },
		Capability{ name: 'kIC3', value: CapabilityValueString{ value: '\\E[2;3~' } },
		Capability{ name: 'kIC4', value: CapabilityValueString{ value: '\\E[2;4~' } },
		Capability{ name: 'kIC5', value: CapabilityValueString{ value: '\\E[2;5~' } },
		Capability{ name: 'kIC6', value: CapabilityValueString{ value: '\\E[2;6~' } },
		Capability{ name: 'kIC7', value: CapabilityValueString{ value: '\\E[2;7~' } },
		Capability{ name: 'kLFT', value: CapabilityValueString{ value: '\\E[1;2D' } },
		Capability{ name: 'kLFT3', value: CapabilityValueString{ value: '\\E[1;3D' } },
		Capability{ name: 'kLFT4', value: CapabilityValueString{ value: '\\E[1;4D' } },
		Capability{ name: 'kLFT5', value: CapabilityValueString{ value: '\\E[1;5D' } },
		Capability{ name: 'kLFT6', value: CapabilityValueString{ value: '\\E[1;6D' } },
		Capability{ name: 'kLFT7', value: CapabilityValueString{ value: '\\E[1;7D' } },
		Capability{ name: 'kNXT', value: CapabilityValueString{ value: '\\E[6;2~' } },
		Capability{ name: 'kNXT3', value: CapabilityValueString{ value: '\\E[6;3~' } },
		Capability{ name: 'kNXT4', value: CapabilityValueString{ value: '\\E[6;4~' } },
		Capability{ name: 'kNXT5', value: CapabilityValueString{ value: '\\E[6;5~' } },
		Capability{ name: 'kNXT6', value: CapabilityValueString{ value: '\\E[6;6~' } },
		Capability{ name: 'kNXT7', value: CapabilityValueString{ value: '\\E[6;7~' } },
		Capability{ name: 'kPRV', value: CapabilityValueString{ value: '\\E[5;2~' } },
		Capability{ name: 'kPRV3', value: CapabilityValueString{ value: '\\E[5;3~' } },
		Capability{ name: 'kPRV4', value: CapabilityValueString{ value: '\\E[5;4~' } },
		Capability{ name: 'kPRV5', value: CapabilityValueString{ value: '\\E[5;5~' } },
		Capability{ name: 'kPRV6', value: CapabilityValueString{ value: '\\E[5;6~' } },
		Capability{ name: 'kPRV7', value: CapabilityValueString{ value: '\\E[5;7~' } },
		Capability{ name: 'kRIT', value: CapabilityValueString{ value: '\\E[1;2C' } },
		Capability{ name: 'kRIT3', value: CapabilityValueString{ value: '\\E[1;3C' } },
		Capability{ name: 'kRIT4', value: CapabilityValueString{ value: '\\E[1;4C' } },
		Capability{ name: 'kRIT5', value: CapabilityValueString{ value: '\\E[1;5C' } },
		Capability{ name: 'kRIT6', value: CapabilityValueString{ value: '\\E[1;6C' } },
		Capability{ name: 'kRIT7', value: CapabilityValueString{ value: '\\E[1;7C' } },
		Capability{ name: 'kUP', value: CapabilityValueString{ value: '\\E[1;2A' } },
		Capability{ name: 'kUP3', value: CapabilityValueString{ value: '\\E[1;3A' } },
		Capability{ name: 'kUP4', value: CapabilityValueString{ value: '\\E[1;4A' } },
		Capability{ name: 'kUP5', value: CapabilityValueString{ value: '\\E[1;5A' } },
		Capability{ name: 'kUP6', value: CapabilityValueString{ value: '\\E[1;6A' } },
		Capability{ name: 'kUP7', value: CapabilityValueString{ value: '\\E[1;7A' } },
		Capability{ name: 'kbs', value: CapabilityValueString{ value: '^?' } },
		Capability{ name: 'kcbt', value: CapabilityValueString{ value: '\\E[Z' } },
		Capability{ name: 'kcub1', value: CapabilityValueString{ value: '\\EOD' } },
		Capability{ name: 'kcud1', value: CapabilityValueString{ value: '\\EOB' } },
		Capability{ name: 'kcuf1', value: CapabilityValueString{ value: '\\EOC' } },
		Capability{ name: 'kcuu1', value: CapabilityValueString{ value: '\\EOA' } },
		Capability{ name: 'kdch1', value: CapabilityValueString{ value: '\\E[3~' } },
		Capability{ name: 'kend', value: CapabilityValueString{ value: '\\EOF' } },
		Capability{ name: 'kent', value: CapabilityValueString{ value: '\\EOM' } },
		Capability{ name: 'kf1', value: CapabilityValueString{ value: '\\EOP' } },
		Capability{ name: 'kf10', value: CapabilityValueString{ value: '\\E[21~' } },
		Capability{ name: 'kf11', value: CapabilityValueString{ value: '\\E[23~' } },
		Capability{ name: 'kf12', value: CapabilityValueString{ value: '\\E[24~' } },
		Capability{ name: 'kf13', value: CapabilityValueString{ value: '\\E[1;2P' } },
		Capability{ name: 'kf14', value: CapabilityValueString{ value: '\\E[1;2Q' } },
		Capability{ name: 'kf15', value: CapabilityValueString{ value: '\\E[1;2R' } },
		Capability{ name: 'kf16', value: CapabilityValueString{ value: '\\E[1;2S' } },
		Capability{ name: 'kf17', value: CapabilityValueString{ value: '\\E[15;2~' } },
		Capability{ name: 'kf18', value: CapabilityValueString{ value: '\\E[17;2~' } },
		Capability{ name: 'kf19', value: CapabilityValueString{ value: '\\E[18;2~' } },
		Capability{ name: 'kf2', value: CapabilityValueString{ value: '\\EOQ' } },
		Capability{ name: 'kf20', value: CapabilityValueString{ value: '\\E[19;2~' } },
		Capability{ name: 'kf21', value: CapabilityValueString{ value: '\\E[20;2~' } },
		Capability{ name: 'kf22', value: CapabilityValueString{ value: '\\E[21;2~' } },
		Capability{ name: 'kf23', value: CapabilityValueString{ value: '\\E[23;2~' } },
		Capability{ name: 'kf24', value: CapabilityValueString{ value: '\\E[24;2~' } },
		Capability{ name: 'kf25', value: CapabilityValueString{ value: '\\E[1;5P' } },
		Capability{ name: 'kf26', value: CapabilityValueString{ value: '\\E[1;5Q' } },
		Capability{ name: 'kf27', value: CapabilityValueString{ value: '\\E[1;5R' } },
		Capability{ name: 'kf28', value: CapabilityValueString{ value: '\\E[1;5S' } },
		Capability{ name: 'kf29', value: CapabilityValueString{ value: '\\E[15;5~' } },
		Capability{ name: 'kf3', value: CapabilityValueString{ value: '\\EOR' } },
		Capability{ name: 'kf30', value: CapabilityValueString{ value: '\\E[17;5~' } },
		Capability{ name: 'kf31', value: CapabilityValueString{ value: '\\E[18;5~' } },
		Capability{ name: 'kf32', value: CapabilityValueString{ value: '\\E[19;5~' } },
		Capability{ name: 'kf33', value: CapabilityValueString{ value: '\\E[20;5~' } },
		Capability{ name: 'kf34', value: CapabilityValueString{ value: '\\E[21;5~' } },
		Capability{ name: 'kf35', value: CapabilityValueString{ value: '\\E[23;5~' } },
		Capability{ name: 'kf36', value: CapabilityValueString{ value: '\\E[24;5~' } },
		Capability{ name: 'kf37', value: CapabilityValueString{ value: '\\E[1;6P' } },
		Capability{ name: 'kf38', value: CapabilityValueString{ value: '\\E[1;6Q' } },
		Capability{ name: 'kf39', value: CapabilityValueString{ value: '\\E[1;6R' } },
		Capability{ name: 'kf4', value: CapabilityValueString{ value: '\\EOS' } },
		Capability{ name: 'kf40', value: CapabilityValueString{ value: '\\E[1;6S' } },
		Capability{ name: 'kf41', value: CapabilityValueString{ value: '\\E[15;6~' } },
		Capability{ name: 'kf42', value: CapabilityValueString{ value: '\\E[17;6~' } },
		Capability{ name: 'kf43', value: CapabilityValueString{ value: '\\E[18;6~' } },
		Capability{ name: 'kf44', value: CapabilityValueString{ value: '\\E[19;6~' } },
		Capability{ name: 'kf45', value: CapabilityValueString{ value: '\\E[20;6~' } },
		Capability{ name: 'kf46', value: CapabilityValueString{ value: '\\E[21;6~' } },
		Capability{ name: 'kf47', value: CapabilityValueString{ value: '\\E[23;6~' } },
		Capability{ name: 'kf48', value: CapabilityValueString{ value: '\\E[24;6~' } },
		Capability{ name: 'kf49', value: CapabilityValueString{ value: '\\E[1;3P' } },
		Capability{ name: 'kf5', value: CapabilityValueString{ value: '\\E[15~' } },
		Capability{ name: 'kf50', value: CapabilityValueString{ value: '\\E[1;3Q' } },
		Capability{ name: 'kf51', value: CapabilityValueString{ value: '\\E[1;3R' } },
		Capability{ name: 'kf52', value: CapabilityValueString{ value: '\\E[1;3S' } },
		Capability{ name: 'kf53', value: CapabilityValueString{ value: '\\E[15;3~' } },
		Capability{ name: 'kf54', value: CapabilityValueString{ value: '\\E[17;3~' } },
		Capability{ name: 'kf55', value: CapabilityValueString{ value: '\\E[18;3~' } },
		Capability{ name: 'kf56', value: CapabilityValueString{ value: '\\E[19;3~' } },
		Capability{ name: 'kf57', value: CapabilityValueString{ value: '\\E[20;3~' } },
		Capability{ name: 'kf58', value: CapabilityValueString{ value: '\\E[21;3~' } },
		Capability{ name: 'kf59', value: CapabilityValueString{ value: '\\E[23;3~' } },
		Capability{ name: 'kf6', value: CapabilityValueString{ value: '\\E[17~' } },
		Capability{ name: 'kf60', value: CapabilityValueString{ value: '\\E[24;3~' } },
		Capability{ name: 'kf61', value: CapabilityValueString{ value: '\\E[1;4P' } },
		Capability{ name: 'kf62', value: CapabilityValueString{ value: '\\E[1;4Q' } },
		Capability{ name: 'kf63', value: CapabilityValueString{ value: '\\E[1;4R' } },
		Capability{ name: 'kf7', value: CapabilityValueString{ value: '\\E[18~' } },
		Capability{ name: 'kf8', value: CapabilityValueString{ value: '\\E[19~' } },
		Capability{ name: 'kf9', value: CapabilityValueString{ value: '\\E[20~' } },
		Capability{ name: 'khome', value: CapabilityValueString{ value: '\\EOH' } },
		Capability{ name: 'kich1', value: CapabilityValueString{ value: '\\E[2~' } },
		Capability{ name: 'kind', value: CapabilityValueString{ value: '\\E[1;2B' } },
		Capability{ name: 'kmous', value: CapabilityValueString{ value: '\\E[<' } },
		Capability{ name: 'knp', value: CapabilityValueString{ value: '\\E[6~' } },
		Capability{ name: 'kpp', value: CapabilityValueString{ value: '\\E[5~' } },
		Capability{ name: 'kri', value: CapabilityValueString{ value: '\\E[1;2A' } },
		Capability{ name: 'rs1', value: CapabilityValueString{ value: '\\E]\\E\\\\\\Ec' } },
		Capability{ name: 'sc', value: CapabilityValueString{ value: '\\E7' } },
	]
}
