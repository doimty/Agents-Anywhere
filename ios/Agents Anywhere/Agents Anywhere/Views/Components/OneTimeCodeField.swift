import SwiftUI

/// One native field preserves selection, paste, accessibility and OTP AutoFill.
/// Its Form row supplies the system background and corner shape.
struct OneTimeCodeField: View {
    @Binding var code: String
    let title: String
    var length = 6

    private var digits: Binding<String> {
        Binding(get: { code }, set: { value in
            code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(length))
        })
    }

    var body: some View {
        Group {
            // `kerning` on a view is iOS 16; the older field keeps the same
            // monospaced, centered digits without extra letter spacing.
            if #available(iOS 16.0, *), AppCompatibility.useNativeUI {
                field.kerning(8)
            } else {
                field
            }
        }
        .multilineTextAlignment(.center)
        .keyboardType(.numberPad).textContentType(.oneTimeCode)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.vertical, 10)
        .accessibilityLabel(title)
    }

    private var field: some View {
        TextField(String(repeating: "0", count: length), text: digits)
            .textFieldStyle(.plain)
            .font(.system(.largeTitle, design: .monospaced).weight(.medium))
    }
}
