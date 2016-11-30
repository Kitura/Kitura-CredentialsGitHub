# Kitura-CredentialsGitHub
Plugin for the Credentials framework that authenticate using GitHub

![Mac OS X](https://img.shields.io/badge/os-Mac%20OS%20X-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)

## Summary
Plugin for [Kitura-Credentials](https://github.com/IBM-Swift/Kitura-Credentials) framework that authenticates using the [GitHub web login with OAuth](https://developer.github.com/v3/oauth/#web-application-flow).

## Table of Contents
* [Swift version](#swift-version)
* [Example of GitHub web login](#example-of-github-web-login)
* [License](#license)

## Swift version
The latest version of Kitura-CredentialsGitHub requires **Swift 3**. You can download this version of the Swift binaries by following this [link](https://swift.org/download/). Compatibility with other Swift versions is not guaranteed.

## Example of GitHub web login
First, create an instance of `CredentialsGitHub` plugin and register it with `Credentials` framework:

```swift
import Credentials
import CredentialsGitHub

let credentials = Credentials()
let gitCredentials = CredentialsGitHub(clientId: gitClientId, clientSecret: gitClientSecret, callbackUrl: serverUrl + "/login/github/callback", userAgent: "my-kitura-app")
credentials.register(gitCredentials)
```

**Where:**

- *gitClientId* is the Client ID of your app in your GitHub Developer application settings
- *gitClientSecret* is the Client Secret of your app in your GitHub Developer application settings
- *callbackUrl* is used to tell the GitHub web login page where the user's browser should be redirected when the login is successful. It should be a URL handled by the server you are writing.
- *userAgent* is an optional argument that passes along a User-Agent of your choice on API calls against GitHub. By default, `Kitura-CredentialsGitHub` is set as the User-Agent. [User-Agent is required when invoking GitHub APIs](https://developer.github.com/v3/#user-agent-required).

Next, specify where to redirect non-authenticated requests:

```swift
credentials.options["failureRedirect"] = "/login/github"
```

Connect `credentials` middleware to requests to `/private`:

```swift
router.all("/private", middleware: credentials)
router.get("/private/data", handler: { request, response, next in
  ...  
  next()
})
```

And call `authenticate` to login with GitHub and to handle the redirect (callback) from the GitHub login web page after a successful login:

```swift
router.get("/login/github", handler: credentials.authenticate(gitCredentials.name))

router.get("/login/github/callback", handler: credentials.authenticate(gitCredentials.name))
```

## License
This library is licensed under Apache 2.0. Full license text is available in [LICENSE](LICENSE.txt).
