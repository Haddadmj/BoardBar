import Foundation

/// Resolves a `BoardRef` into a `Board`. Read-only: there is no mutating
/// document anywhere in this type, and no code path that writes to a project.
public struct BoardFetcher: Sendable {
    private let transport: any GitHubTransport
    private let itemLimit = 100

    public init(transport: any GitHubTransport = LiveGitHubTransport()) {
        self.transport = transport
    }

    public func fetch(
        _ ref: BoardRef, token: String, now: Date = Date()
    ) async throws(GitHubError) -> Board {
        let layout = try await fetchLayout(ref, token: token)
        return try await fetchItems(ref, layout: layout, token: token, now: now)
    }

    // MARK: - Pass 1: columns and filter

    struct Layout {
        let groupFieldName: String
        let columnNames: [String]
        let filter: String
        let source: Board.ColumnSource
        /// A filter that was read off the view but could not be honoured,
        /// because the fallback path has no way to apply it. Non-nil means the
        /// board shown is wider than the same view in a browser.
        let unappliedFilter: String?
        let projectTitle: String?
        let viewName: String?
    }

    private func rootField(_ ref: BoardRef) -> String {
        ref.ownerKind == .users ? "user" : "organization"
    }

    /// Two round trips are unavoidable: the item query needs the view's filter
    /// as an *argument*, and GraphQL cannot feed a value from one part of a
    /// document into another. Client-side filtering was the alternative and it
    /// would mean reimplementing GitHub's filter syntax, so the extra request
    /// is the cheaper mistake. At a 5-minute poll this is 24 requests an hour
    /// against a 5000-point budget.
    private func fetchLayout(_ ref: BoardRef, token: String) async throws(GitHubError) -> Layout {
        let viewFragment = ref.viewNumber.map { number in
            """
            view(number: \(number)) {
              name
              layout
              filter
              verticalGroupByFields(first: 1) {
                nodes {
                  __typename
                  ... on ProjectV2SingleSelectField { name options { name } }
                }
              }
            }
            """
        } ?? ""

        let query = """
        query($owner: String!) {
          \(rootField(ref))(login: $owner) {
            projectV2(number: \(ref.projectNumber)) {
              title
              statusField: field(name: "Status") {
                ... on ProjectV2SingleSelectField { name options { name } }
              }
              \(viewFragment)
            }
          }
        }
        """

        let data = try await transport.post(
            query: query, variables: ["owner": ref.owner], token: token
        )
        let json = try decodeGraphQL(data)
        guard
            let owner = json[rootField(ref)] as? [String: Any],
            let project = owner["projectV2"] as? [String: Any]
        else { throw .boardNotFound }

        var droppedFilter: String?
        // Read off the same nodes the layout query already visits, so a tab
        // label costs no extra request.
        let projectTitle = project["title"] as? String
        var viewName: String?

        // Path 1: mirror the named view.
        if let viewNumber = ref.viewNumber {
            guard let view = project["view"] as? [String: Any] else {
                throw .viewNotFound(number: viewNumber)
            }
            let filter = view["filter"] as? String ?? ""
            viewName = view["name"] as? String
            let isBoard = (view["layout"] as? String) == "BOARD_LAYOUT"
            let groupBy = ((view["verticalGroupByFields"] as? [String: Any])?["nodes"]
                as? [[String: Any]])?.first

            if isBoard, let groupBy {
                let typeName = groupBy["__typename"] as? String ?? "an unknown field type"
                // Only single-select grouping renders as columns today. An
                // iteration or multi-select view falls back rather than
                // failing, because a fallback board is more useful than none.
                if typeName == "ProjectV2SingleSelectField",
                    let name = groupBy["name"] as? String,
                    let options = groupBy["options"] as? [[String: Any]]
                {
                    return Layout(
                        groupFieldName: name,
                        columnNames: options.compactMap { $0["name"] as? String },
                        filter: filter,
                        source: .view,
                        unappliedFilter: nil,
                        projectTitle: projectTitle,
                        viewName: viewName
                    )
                }
            }
            // Grouping was unsupported, so the code below falls back to the
            // Status field — which cannot carry this view's filter. Remember it
            // so the board can say so rather than quietly showing more.
            droppedFilter = filter.isEmpty ? nil : filter
        }

        // Path 2: the project's own Status field, unfiltered.
        guard
            let status = project["statusField"] as? [String: Any],
            let name = status["name"] as? String,
            let options = status["options"] as? [[String: Any]]
        else { throw .malformedResponse("project has no Status single-select field") }

        return Layout(
            groupFieldName: name,
            columnNames: options.compactMap { $0["name"] as? String },
            filter: "",
            source: .statusFieldFallback,
            unappliedFilter: droppedFilter,
            projectTitle: projectTitle,
            // Kept even here. The columns came from the Status field rather
            // than the view, but the tab is still the view the maintainer
            // configured, and the board says so itself through `columnSource`.
            viewName: viewName
        )
    }

    // MARK: - Pass 2: items

    private func fetchItems(
        _ ref: BoardRef, layout: Layout, token: String, now: Date
    ) async throws(GitHubError) -> Board {
        // No pagination: the design target is ~30 items. Truncation past 100 is
        // surfaced on the board rather than hidden.
        let query = """
        query($owner: String!, $q: String!) {
          \(rootField(ref))(login: $owner) {
            projectV2(number: \(ref.projectNumber)) {
              items(first: \(itemLimit), query: $q) {
                totalCount
                nodes {
                  fieldValues(first: 20) {
                    nodes {
                      ... on ProjectV2ItemFieldSingleSelectValue {
                        name
                        field { ... on ProjectV2FieldCommon { name } }
                      }
                    }
                  }
                  content {
                    ... on Issue {
                      number
                      title
                      url
                      updatedAt
                      repository { nameWithOwner }
                      labels(first: 5) { nodes { name color } }
                    }
                  }
                }
              }
            }
          }
        }
        """

        let data = try await transport.post(
            query: query,
            variables: ["owner": ref.owner, "q": layout.filter],
            token: token
        )
        let json = try decodeGraphQL(data)
        guard
            let owner = json[rootField(ref)] as? [String: Any],
            let project = owner["projectV2"] as? [String: Any],
            let items = project["items"] as? [String: Any],
            let nodes = items["nodes"] as? [[String: Any]]
        else { throw .malformedResponse("no items in response") }

        var buckets: [String: [Card]] = [:]
        for node in nodes {
            guard let card = Self.card(from: node) else { continue }
            let column = Self.groupValue(of: node, fieldNamed: layout.groupFieldName)
                ?? Self.noValueColumn
            buckets[column, default: []].append(card)
        }

        var columns = layout.columnNames.map { Column(name: $0, cards: buckets[$0] ?? []) }
        // GitHub shows unassigned items in their own column; mirroring that is
        // more faithful than dropping them, but only when it is non-empty.
        if let orphans = buckets[Self.noValueColumn], !orphans.isEmpty {
            columns.insert(Column(name: Self.noValueColumn, cards: orphans), at: 0)
        }

        return Board(
            columns: columns,
            columnSource: layout.source,
            fetchedAt: now,
            totalCount: items["totalCount"] as? Int ?? 0,
            unappliedFilter: layout.unappliedFilter,
            projectTitle: layout.projectTitle,
            viewName: layout.viewName
        )
    }

    static let noValueColumn = "No Status"

    static func groupValue(of node: [String: Any], fieldNamed name: String) -> String? {
        guard
            let values = (node["fieldValues"] as? [String: Any])?["nodes"] as? [[String: Any]]
        else { return nil }
        for value in values {
            guard
                let field = value["field"] as? [String: Any],
                field["name"] as? String == name
            else { continue }
            return value["name"] as? String
        }
        return nil
    }

    static func card(from node: [String: Any]) -> Card? {
        // Draft items and pull requests decode to an empty `content` because
        // the query only spreads `... on Issue`. Skipping them is deliberate.
        guard
            let content = node["content"] as? [String: Any],
            let number = content["number"] as? Int,
            let title = content["title"] as? String,
            let urlString = content["url"] as? String,
            let url = URL(string: urlString),
            let repo = (content["repository"] as? [String: Any])?["nameWithOwner"] as? String,
            let updatedString = content["updatedAt"] as? String,
            let updatedAt = ISO8601DateFormatter().date(from: updatedString)
        else { return nil }

        let labels = ((content["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            .compactMap { label -> IssueLabel? in
                guard let name = label["name"] as? String, let color = label["color"] as? String
                else { return nil }
                return IssueLabel(name: name, color: color)
            }

        return Card(
            number: number, title: title, url: url,
            repository: repo, updatedAt: updatedAt, labels: labels
        )
    }

    // MARK: - GraphQL envelope

    private func decodeGraphQL(_ data: Data) throws(GitHubError) -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .malformedResponse("body was not a JSON object")
        }
        // A GraphQL error arrives with HTTP 200, so this is the only place a
        // bad token or a missing board is detected on the happy path.
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("bad credentials") }) {
                throw .unauthorized
            }
            throw .graphQL(messages)
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw .malformedResponse("no data field")
        }
        return payload
    }
}
