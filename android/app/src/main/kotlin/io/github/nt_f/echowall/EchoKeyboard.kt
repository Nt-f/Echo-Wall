package io.github.nt_f.echowall

import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo

/* A keyboard for the apps the screen app starts (a YouTube client's search): the Echo has no input method at all, so
 * nothing could be typed into them.  Root's main.sh (screen_grants) switches it on for the screen app's package and
 * makes it the default when there is none.  The screen app itself keeps its own keyboard (lib/keyboard.dart: round
 * screens, the WebView's key events), so this one does not come up for it.
 *
 * android.inputmethodservice.KeyboardView: deprecated, but in every Android an Echo runs (7 to 9) and a few kB, where a
 * Flutter view would be a second engine; in a ":kb" process of its own, apart from the Flutter app. */
@Suppress("DEPRECATION")
class EchoKeyboard : InputMethodService(), KeyboardView.OnKeyboardActionListener {
    private lateinit var view: KeyboardView
    private lateinit var letters: Keyboard
    private lateinit var symbols: Keyboard
    private var caps = false

    override fun onCreateInputView(): View {
        letters = Keyboard(this, R.xml.kb_letters)
        symbols = Keyboard(this, R.xml.kb_symbols)
        view = layoutInflater.inflate(R.layout.keyboard, null) as KeyboardView
        view.keyboard = letters
        view.isPreviewEnabled = false
        view.setOnKeyboardActionListener(this)
        return view
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        if (::view.isInitialized) { setCaps(false); view.keyboard = letters }
    }

    // the screen app types with its own; an Echo has no hardware keyboard, so a request to show is always one
    override fun onShowInputRequested(flags: Int, configChange: Boolean) = currentInputEditorInfo?.packageName != packageName
    override fun onEvaluateInputViewShown() = currentInputEditorInfo?.packageName != packageName
    // landscape on a 480 px screen: Android would go full screen (an extract view over the app); the app stays seen
    override fun onEvaluateFullscreenMode() = false

    private fun setCaps(on: Boolean) {
        caps = on
        if (::letters.isInitialized) letters.isShifted = on
        if (::view.isInitialized) view.invalidateAllKeys()
    }

    override fun onKey(code: Int, codes: IntArray?) {
        val ic = currentInputConnection ?: return
        when (code) {
            Keyboard.KEYCODE_DELETE -> sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
            Keyboard.KEYCODE_SHIFT -> setCaps(!caps)
            Keyboard.KEYCODE_MODE_CHANGE -> view.keyboard = if (view.keyboard === letters) symbols else letters
            Keyboard.KEYCODE_CANCEL -> requestHideSelf(0)
            10 -> {
                // a search field's "search", a form's "go": the action the field asks for, else a plain Enter
                val action = (currentInputEditorInfo?.imeOptions ?: 0) and EditorInfo.IME_MASK_ACTION
                val none = ((currentInputEditorInfo?.imeOptions ?: 0) and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
                if (!none && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) ic.performEditorAction(action)
                else sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
            }
            else -> {
                var c = code.toChar()
                if (caps && c.isLetter()) { c = c.uppercaseChar(); setCaps(false) }      // one capital, as a phone's
                ic.commitText(c.toString(), 1)
            }
        }
    }

    override fun onPress(code: Int) {}
    override fun onRelease(code: Int) {}
    override fun onText(text: CharSequence?) { currentInputConnection?.commitText(text, 1) }
    override fun swipeLeft() {}
    override fun swipeRight() {}
    override fun swipeDown() { requestHideSelf(0) }
    override fun swipeUp() {}
}
