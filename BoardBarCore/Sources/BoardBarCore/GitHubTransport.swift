import Foundation

/// The seam that keeps `BoardFetcher` testable without a network or a token.
public protocol GitHubTransport: Sendable {
    /// Posts a GraphQL document and returns the raw response body.
    func post(query: String, variables: [String: String], token: String) async throws(GitHubError) -> Data
}

public struct LiveGitHubTransport: GitHubTransport {
    private let endpoint = URL(string: "https://api.github.com/graphql")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func post(
        query: String, variables: [String: String], token: String
    ) async throws(GitHubError) -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BoardBar", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // The token must never reach a message that could be shown or
            // logged, so the URLError description is used rather than anything
            // derived from the request.
            throw .transport((error as NSError).localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .malformedResponse("no HTTP response")
        }
        switch http.statusCode {
        case 200: return data
        case 401: throw .unauthorized
        case 403:
            // GitHub returns 403 for both rate limiting and scope problems, and
            // they need different messages.
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                throw .rateLimited
            }
            throw .forbidden("check that your token has the read:project scope")
        default: throw .http(status: http.statusCode)
        }
    }
}
