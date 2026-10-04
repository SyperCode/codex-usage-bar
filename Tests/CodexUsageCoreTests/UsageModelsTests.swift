import XCTest
@testable import CodexUsageCore

final class UsageModelsTests: XCTestCase {
    func testDecodesCodexRateLimitsAndCalculatesRemainingUsage() throws {
        let json = #"""
        {
          "ordinaryUsageAllowed": true,
          "rateLimits": {
            "limitId": "codex",
            "primary": {
              "usedPercent": 23,
              "windowDurationMins": 300,
              "resetsAt": 1790980506
            },
            "secondary": {
              "usedPercent": 46,
              "windowDurationMins": 10080,
              "resetsAt": 1791308532
            },
            "credits": {
              "hasCredits": false,
              "unlimited": false,
              "balance": "0"
            },
            "planType": "plus"
          },
          "rateLimitsByLimitId": null,
          "rateLimitResetCredits": {
            "availableCount": 0
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(RateLimitsReadResponse.self, from: json)
        let snapshot = response.usageSnapshot

        XCTAssertEqual(snapshot.primary?.remainingPercent, 77)
        XCTAssertEqual(snapshot.primary?.compactDuration, "5h")
        XCTAssertEqual(snapshot.secondary?.remainingPercent, 54)
        XCTAssertEqual(snapshot.secondary?.compactDuration, "7d")
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.ordinaryUsageAllowed, true)
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(
            UsageWindow(usedPercent: 130, windowDurationMinutes: nil, resetsAt: nil).remainingPercent,
            0
        )
        XCTAssertEqual(
            UsageWindow(usedPercent: -20, windowDurationMinutes: nil, resetsAt: nil).remainingPercent,
            100
        )
    }

    func testMenuBarTitlesStayCompactAndShowBothLimits() {
        let snapshot = UsageSnapshot(
            primary: UsageWindow(
                usedPercent: 33,
                windowDurationMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_790_980_506)
            ),
            secondary: UsageWindow(
                usedPercent: 47,
                windowDurationMinutes: 10_080,
                resetsAt: Date(timeIntervalSince1970: 1_791_308_532)
            ),
            credits: nil,
            planType: "plus",
            ordinaryUsageAllowed: true,
            availableResetCredits: 0
        )

        let formatter = MenuBarTitleFormatter(
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "Europe/Moscow")!
        )

        XCTAssertEqual(
            formatter.string(from: snapshot, mode: .expanded),
            "5h 67% · wk 53%"
        )

        XCTAssertEqual(
            formatter.string(from: snapshot, mode: .compact),
            "5h 67% until 01:35"
        )

        XCTAssertEqual(
            formatter.string(from: snapshot, mode: .battery),
            "67%"
        )

        let russianFormatter = MenuBarTitleFormatter(
            language: .russian,
            locale: Locale(identifier: "ru_RU"),
            timeZone: TimeZone(identifier: "Europe/Moscow")!
        )

        XCTAssertEqual(
            russianFormatter.string(from: snapshot, mode: .compact),
            "5ч 67% до 01:35"
        )

        XCTAssertEqual(
            russianFormatter.string(from: snapshot, mode: .expanded),
            "5ч 67% · нед 53%"
        )

        XCTAssertEqual(
            russianFormatter.string(from: snapshot, mode: .battery),
            "67%"
        )
    }
}
