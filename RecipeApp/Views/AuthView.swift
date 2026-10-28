import AuthenticationServices
import SwiftUI

/// Вход и регистрация: через Apple или по email и паролю.
struct AuthView: View {
    var reason: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("cityId") private var cityId = AppConfig.defaultCityId

    enum Mode: String, CaseIterable, Identifiable {
        case login = "Вход", register = "Регистрация"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var passwordRepeat = ""
    @State private var displayName = ""
    @State private var acceptedRules = false
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var showVerify = false

    private var session: AuthSession { .shared }

    private var formError: String? {
        let e = email.trimmed
        if e.isEmpty || !e.contains("@") || !e.contains(".") { return "Введите email" }
        if mode == .login { return password.isEmpty ? "Введите пароль" : nil }
        if displayName.trimmed.isEmpty { return "Введите имя" }
        if password.count < 8 { return "Пароль — минимум 8 символов" }
        if password.rangeOfCharacter(from: .decimalDigits) == nil || password.rangeOfCharacter(from: .letters) == nil {
            return "Пароль должен содержать буквы и цифры"
        }
        if password != passwordRepeat { return "Пароли не совпадают" }
        if !acceptedRules { return "Примите правила сообщества" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let reason {
                    Section { Text(reason).font(.footnote) }
                }

                Section {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Быстрый вход без пароля. Apple может скрыть ваш настоящий email.")
                }

                Section {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if mode == .register {
                        TextField("Имя или ник", text: $displayName)
                            .textContentType(.nickname)
                    }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                    if mode == .register {
                        SecureField("Повторите пароль", text: $passwordRepeat)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if mode == .register {
                        Text("Пароль — минимум 8 символов, буквы и цифры. Город для цен — из настроек.")
                    }
                }

                if mode == .register {
                    Section {
                        Toggle(isOn: $acceptedRules) {
                            Text("Принимаю правила сообщества: без оскорблений, спама и опасного контента. Нарушителей блокируем.")
                                .font(.footnote)
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).font(.footnote) }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else { Text(mode == .login ? "Войти" : "Зарегистрироваться").bold() }
                            Spacer()
                        }
                    }
                    .disabled(isWorking || formError != nil)
                    if mode == .login {
                        NavigationLink("Забыли пароль?") {
                            ForgotPasswordView(initialEmail: email.trimmed) { dismiss() }
                        }
                    }
                } footer: {
                    if let formError, !(email.isEmpty && password.isEmpty) {
                        Text(formError)
                    }
                }
            }
            .navigationTitle(mode == .login ? "Вход" : "Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .onChange(of: mode) { _, _ in errorText = nil }
            .navigationDestination(isPresented: $showVerify) {
                VerifyEmailView { dismiss() }
                    .navigationBarBackButtonHidden()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Позже") { dismiss() } }
                    }
            }
        }
    }

    private func submit() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .login:
                try await session.login(email: email.trimmed, password: password)
            case .register:
                try await session.register(email: email.trimmed, password: password,
                                           displayName: displayName.trimmed, cityId: cityId)
                showVerify = true  // письмо с кодом уже отправлено
                return
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorText = "Не удалось войти через Apple: \(error.localizedDescription)"
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                errorText = "Apple не вернул данные для входа"
                return
            }
            isWorking = true
            defer { isWorking = false }
            do {
                try await session.signInWithApple(identityToken: token, fullName: credential.fullName)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

/// Кнопка-заглушка для действий, требующих входа.
struct LoginRequiredButton: View {
    let title: String
    @State private var showAuth = false

    var body: some View {
        Button {
            showAuth = true
        } label: {
            Label(title, systemImage: "person.crop.circle.badge.plus")
        }
        .sheet(isPresented: $showAuth) { AuthView(reason: title) }
    }
}
