package main

import "strings"

// jniSafeText makes Go text safe for JNI NewStringUTF, which expects
// "modified UTF-8": invalid bytes, NUL and characters outside the BMP (flag
// emoji in proxy names are common in core errors) would make CheckJNI abort
// the app or garble the message. They become U+FFFD / a space.
func jniSafeText(text string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r == 0:
			return ' '
		case r > 0xFFFF:
			return '�'
		default:
			return r
		}
	}, strings.ToValidUTF8(text, "�"))
}
