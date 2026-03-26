import SwiftUI
import SwiftData
import UIKit

struct LoginView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("username") private var storedUsername = ""

    @State private var inputUsername = ""
    @State private var password = ""

    @State private var goToApp = false
    @State private var goToSignUp = false
    @State private var isPasswordVisible = false
    @State private var errorMessage = ""
    @State private var acceptedUser = true

    var body: some View {
        NavigationStack {
            VStack {
                Text("Navig-Aid")
                    .font(.largeTitle)
                    .padding()

                TextField("Username", text: $inputUsername)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                ZStack(alignment: .trailing) {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 10)
                    }
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

                if !acceptedUser {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                Button("Login") {
                    Task {
                        await authenticateUser(
                            username: inputUsername,
                            password: password
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()

                .navigationDestination(isPresented: $goToApp) {
                    ContentView()
                }

                Button("Sign Up") {
                    goToSignUp = true
                }
                .navigationDestination(isPresented: $goToSignUp) {
                    SignUpView()
                }
            }
        }
    }

    @MainActor
    func authenticateUser(username: String, password: String) async {
        let users = await Database.shared.fetchUsers()

        guard let user = users.first(where: { $0.username == username }) else {
            failLogin()
            return
        }

        let isValid = verifyPassword(
            input: password,
            storedHash: user.hashedPassword,
            salt: user.saltedPassword
        )
    print(user.hashedPassword, user.saltedPassword)
        if isValid {
            isLoggedIn = true
            storedUsername = user.username
            goToApp = true
            acceptedUser = true
            errorMessage = ""
        } else {
            failLogin()
        }
    }

    @MainActor
    private func failLogin() {
        acceptedUser = false
        errorMessage = "Incorrect username or password"
        UIAccessibility.post(notification: .announcement, argument: errorMessage)
    }
}

#Preview {
    LoginView()
}
