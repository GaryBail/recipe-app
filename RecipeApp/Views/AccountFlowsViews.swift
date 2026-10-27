import SwiftUI

/// Ввод 6-значного кода из письма.
struct CodeField: View {
    @Binding var code: String

    var body: some View {
        TextField("Код из письма", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.title2.monospacedDigit())
            .onChange(of: code) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(6))
                if digits != new { code = digits }
            }
    }
}

/// Подтверждение email после регистрации.
struct VerifyEmailView: View {
    var onDone: () -> Void = {}

    @State private var code = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var resendIn = 60
    private var session: AuthSession { .shared }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Text("Мы отправили код на \(session.user?.email ?? "вашу почту"). Он действует 15 минут.")
                    .font(.footnote)
                CodeField(code: $code)
            } footer: {
                Text("Подтверждённый email нужен, чтобы публиковать сборки и ставить оценки, и чтобы восстановить пароль.")
            }

            Section {
                Button {
                    Task { await verify() }
                } label: {
                    HStack { Spacer(); if isWorking { ProgressView() } else { Text("Подтвердить").bold() }; Spacer() }
                }
                .disabled(code.count != 6 || isWorking)

                Button(resendIn > 0 ? "Отправить код ещё раз (\(resendIn) с)" : "Отправить код ещё раз") {
                    Task { await resend() }
                }
                .disabled(resendIn > 0 || isWorking)
            }

            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Подтверждение email")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in if resendIn > 0 { resendIn -= 1 } }
    }

    private func verify() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.verifyEmail(code: code)
            onDone()
        } catch {
            message = error.localizedDescription
            code = ""
        }
    }

    private func resend() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.resendVerificationCode()
            message = "Новый код отправлен"
            resendIn = 60
        } catch {
            message = error.localizedDescription
        }
    }
}

/// «Забыли пароль?»: email → код из письма + новый пароль.
struct ForgotPasswordView: View {
    var initialEmail = ""
    var onDone: () -> Void = {}

    @State private var email = ""
    @State private var codeSent = false
    @State private var code = ""
    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var message: String?
    @State private var isWorking = false
    private var session: AuthSession { .shared }

    private var passwordError: String? {
        if password.count < 8 { return "Минимум 8 символов" }
        if password.rangeOfCharacter(from: .decimalDigits) == nil || password.rangeOfCharacter(from: .letters) == nil {
            return "Нужны буквы и цифры"
        }
        if password != passwordRepeat { return "Пароли не совпадают" }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(codeSent)
                if !codeSent {
                    Button("Получить код") { Task { await sendCode() } }
                        .disabled(!email.contains("@") || isWorking)
                }
            } footer: {
                if !codeSent {
                    Text("Пришлём код для сброса пароля, если такой email зарегистрирован.")
                }
            }

            if codeSent {
                Section {
                    CodeField(code: $code)
                    SecureField("Новый пароль", text: $password).textContentType(.newPassword)
                    SecureField("Повторите пароль", text: $passwordRepeat).textContentType(.newPassword)
                } footer: {
                    if !password.isEmpty, let passwordError { Text(passwordError) }
                }
                Section {
                    Button {
                        Task { await reset() }
                    } label: {
                        HStack { Spacer(); if isWorking { ProgressView() } else { Text("Сменить пароль").bold() }; Spacer() }
                    }
                    .disabled(code.count != 6 || passwordError != nil || isWorking)
                    Button("Отправить код ещё раз") { Task { await sendCode() } }
                        .disabled(isWorking)
                }
            }

            if let message {
                Section { Text(message).font(.footnote) }
            }
        }
        .navigationTitle("Восстановление пароля")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if email.isEmpty { email = initialEmail } }
    }

    private func sendCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.forgotPassword(email: email.trimmed)
            codeSent = true
            message = "Если аккаунт с этим email есть, код уже в почте. Проверьте и папку «Спам»."
        } catch {
            message = error.localizedDescription
        }
    }

    private func reset() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.resetPassword(email: email.trimmed, code: code, newPassword: password)
            onDone()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var message: String?
    @State private var isWorking = false

    private var valid: Bool {
        !old.isEmpty && password.count >= 8 && password == passwordRepeat
            && password.rangeOfCharacter(from: .decimalDigits) != nil
            && password.rangeOfCharacter(from: .letters) != nil
    }

    var body: some View {
        Form {
            Section {
                SecureField("Текущий пароль", text: $old).textContentType(.password)
                SecureField("Новый пароль", text: $password).textContentType(.newPassword)
                SecureField("Повторите новый пароль", text: $passwordRepeat).textContentType(.newPassword)
            } footer: {
                Text("Минимум 8 символов, буквы и цифры. На других устройствах потребуется войти заново.")
            }
            Section {
                Button("Сменить пароль") {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        do {
                            try await AuthSession.shared.changePassword(old: old, new: password)
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(!valid || isWorking)
            }
            if let message {
                Section { Text(message).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Смена пароля")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Подсказка подтвердить email (для действий, где это нужно).
struct VerifyEmailPrompt: View {
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Label("Подтвердите email, чтобы публиковать и оценивать", systemImage: "envelope.badge")
        }
        .sheet(isPresented: $show) {
            NavigationStack {
                VerifyEmailView { show = false }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { show = false } } }
            }
        }
    }
}
