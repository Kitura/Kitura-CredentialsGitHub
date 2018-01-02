/**
 * Copyright IBM Corporation 2016, 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Kitura
import KituraNet
import LoggerAPI
import Credentials
import Foundation

// MARK CredentialsGitHub

/// Authentication using GitHub web login with OAuth.
/// See [GitHub manual](https://developer.github.com/v3/oauth/#web-application-flow)
/// for more information.
public class CredentialsGitHub: CredentialsPluginProtocol {

    private var clientId: String

    private var clientSecret: String

    private let scopes: [String]

    /// The URL that GitHub redirects back to.
    public var callbackUrl: String

    /// The User-Agent to be passed along on GitHub API calls.
    /// User-Agent must be set in order to access GitHub API (i.e., to get user profile).
    /// See [GitHub manual](https://developer.github.com/v3/#user-agent-required)
    /// for more information.
    public private(set) var userAgent: String

    /// The name of the plugin.
    public let name = "GitHub"

    /// An indication as to whether the plugin is redirecting or not.
    public let redirecting = true

    /// User profile cache.
    public var usersCache: NSCache<NSString, BaseCacheElement>?

    /// A delegate for `UserProfile` manipulation.
    public let userProfileDelegate: UserProfileDelegate?

    /// Initialize a `CredentialsGitHub` instance.
    ///
    /// - Parameter clientId: The Client ID of the app in the GitHub Developer applications.
    /// - Parameter clientSecret: The Client Secret of the app in the GitHub Developer applications.
    /// - Parameter callbackUrl: The URL that GitHub redirects back to.
    public init (clientId: String, clientSecret: String, callbackUrl: String, userAgent: String?=nil, options: [String: Any] = [:]) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.callbackUrl = callbackUrl
        self.scopes = options[CredentialsGitHubOptions.scopes] as? [String] ?? []
        self.userAgent = userAgent ?? "Kitura-CredentialsGitHub"
        self.userProfileDelegate = options[CredentialsGitHubOptions.userProfileDelegate] as? UserProfileDelegate
    }

    /// Authenticate incoming request using GitHub web login with OAuth.
    ///
    /// - Parameter request: The `RouterRequest` object used to get information
    ///                     about the request.
    /// - Parameter response: The `RouterResponse` object used to respond to the
    ///                       request.
    /// - Parameter options: The dictionary of plugin specific options.
    /// - Parameter onSuccess: The closure to invoke in the case of successful authentication.
    /// - Parameter onFailure: The closure to invoke in the case of an authentication failure.
    /// - Parameter onPass: The closure to invoke when the plugin doesn't recognize the
    ///                     authentication data in the request.
    /// - Parameter inProgress: The closure to invoke to cause a redirect to the login page in the
    ///                     case of redirecting authentication.
    public func authenticate (request: RouterRequest, response: RouterResponse,
                              options: [String:Any], onSuccess: @escaping (UserProfile) -> Void,
                              onFailure: @escaping (HTTPStatusCode?, [String:String]?) -> Void,
                              onPass: @escaping (HTTPStatusCode?, [String:String]?) -> Void,
                              inProgress: @escaping () -> Void) {
        if let code = request.queryParameters["code"] {
            // query contains code: exchange code for access token
            var requestOptions: [ClientRequest.Options] = []
            requestOptions.append(.schema("https://"))
            requestOptions.append(.hostname("github.com"))
            requestOptions.append(.method("POST"))
            requestOptions.append(.path("/login/oauth/access_token?client_id=\(clientId)&redirect_uri=\(callbackUrl)&client_secret=\(clientSecret)&code=\(code)"))
            var headers = [String:String]()
            headers["Accept"] = "application/json"
            requestOptions.append(.headers(headers))

            let requestForToken = HTTP.request(requestOptions) { fbResponse in
                if let fbResponse = fbResponse, fbResponse.statusCode == .OK {
                    // get user profile with access token
                    do {
                        var body = Data()
                        try fbResponse.readAllData(into: &body)
                        //var jsonBody = JSON(data: body)
                        //if let token = jsonBody["access_token"].string {
                        if var jsonBody = try JSONSerialization.jsonObject(with: body, options: []) as? [String : Any],
                        let token = jsonBody["access_token"] as? String {
                            requestOptions = []
                            requestOptions.append(.schema("https://"))
                            requestOptions.append(.hostname("api.github.com"))
                            requestOptions.append(.method("GET"))
                            requestOptions.append(.path("/user"))
                            headers = [String:String]()
                            headers["Accept"] = "application/json"
                            headers["User-Agent"] = self.userAgent
                            headers["Authorization"] = "token \(token)"
                            requestOptions.append(.headers(headers))

                            let requestForProfile = HTTP.request(requestOptions) { profileResponse in
                                if let profileResponse = profileResponse, profileResponse.statusCode == .OK {
                                    do {
                                        body = Data()
                                        try profileResponse.readAllData(into: &body)
                                        //jsonBody = JSON(data: body)
                                        //if let userDictionary = jsonBody.dictionaryObject,
                                        if let userDictionary = try JSONSerialization.jsonObject(with: body, options: []) as? [String : Any],
                                        let userProfile = self.createUserProfile(from: userDictionary) {
                                            if let delegate = self.userProfileDelegate {
                                                //delegate.update(userProfile: userProfile, from: jsonBody.dictionaryValue)
                                                delegate.update(userProfile: userProfile, from: userDictionary)
                                            }

                                            onSuccess(userProfile)
                                            return
                                        }
                                    }
                                    catch {
                                        Log.error("Failed to read \(self.name) response")
                                    }
                                }
                                else {
                                    onFailure(nil, nil)
                                }
                            }
                            requestForProfile.end()
                        }
                    }
                    catch {
                        Log.error("Failed to read \(self.name) response")
                    }
                }
                else {
                    onFailure(nil, nil)
                }
            }
            requestForToken.end()
        }
        else {
            // Log in
            var scopeParameters = ""

            if !scopes.isEmpty {
                scopeParameters = "&scope="

                for scope in scopes {
                    // space delimited list: https://developer.github.com/v3/oauth/#parameters
                    // trailing space character is probably OK
                    scopeParameters.append(scope + " ")
                }
            }

            do {
                try response.redirect("https://github.com/login/oauth/authorize?client_id=\(clientId)&redirect_uri=\(callbackUrl)&response_type=code\(scopeParameters)")
                inProgress()
            }
            catch {
                Log.error("Failed to redirect to \(name) login page")
            }
        }
    }

    // GitHub user profile response format looks like this:
    /*
     {
         "login" : "<string>",
         "id" : <int>,
         "avatar_url" : "<string>",
         "gravatar_id" : "",
         "url" : "<string>",
         "html_url" : "<string>",
         "followers_url" : "<string>",
         "following_url" : "<string>",
         "gists_url" : "<string>",
         "starred_url" : "<string>",
         "subscriptions_url" : "<string>",
         "organizations_url" : "<string>",
         "repos_url" : "<string>",
         "events_url" : "<string>",
         "received_events_url" : "<string>",
         "type" : "User",
         "site_admin" : <bool>,
         "name" : "<string>",
         "company" : "<string>",
         "blog" : null,
         "location" : null,
         "email" : null,
         "hireable" : null,
         "bio" : null,
         "public_repos" : <int>,
         "public_gists" : <int>,
         "followers" : <int>,
         "following" : <int>,
         "created_at" : "<time stamp string>",
         "updated_at" : "<time stamp string>"
     }
     */
    private func createUserProfile(from userDictionary: [String: Any]) -> UserProfile? {
        guard let id = userDictionary["id"] as? Int else {
            return nil
        }

        let name = userDictionary["name"] as? String ?? ""

        var userProfileEmails: [UserProfile.UserProfileEmail]?

        if let email = userDictionary["email"] as? String {
            userProfileEmails = [UserProfile.UserProfileEmail(value: email, type: "public")]
        }

        var userProfilePhotos: [UserProfile.UserProfilePhoto]?

        if let photoURL = userDictionary["avatar_url"] as? String {
            userProfilePhotos = [UserProfile.UserProfilePhoto(photoURL)]
        }

        return UserProfile(id: String(id), displayName: name, provider: self.name, emails: userProfileEmails, photos: userProfilePhotos)
    }
}
