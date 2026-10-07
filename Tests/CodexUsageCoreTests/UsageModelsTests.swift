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

    func testLimitAlertPolicyUsesWarningAndFixedCriticalThresholds() {
        XCTAssertEqual(LimitAlertPolicy.level(remainingPercent: 21, warningThreshold: 20), .none)
        XCTAssertEqual(LimitAlertPolicy.level(remainingPercent: 20, warningThreshold: 20), .warning)
        XCTAssertEqual(LimitAlertPolicy.level(remainingPercent: 11, warningThreshold: 90), .warning)
        XCTAssertEqual(LimitAlertPolicy.level(remainingPercent: 10, warningThreshold: 90), .critical)
        XCTAssertEqual(LimitAlertPolicy.level(remainingPercent: 6, warningThreshold: 10), .critical)
    }

    func testUsagePeriodsAreDerivedFromServerDuration() {
        XCTAssertEqual(UsagePeriodKind(durationMinutes: 300), .fiveHour)
        XCTAssertEqual(UsagePeriodKind(durationMinutes: 10_080), .weekly)
        XCTAssertEqual(UsagePeriodKind(durationMinutes: 43_200), .monthly)
        XCTAssertEqual(
            UsagePeriodKind(durationMinutes: 43_200).title(language: .russian),
            "Месячный лимит"
        )
        XCTAssertEqual(
            UsagePeriodKind(durationMinutes: 43_200).shortLabel(language: .english),
            "mo"
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

    func testSingleMonthlyLimitDoesNotInventASecondLimit() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: UsageWindow(
                usedPercent: 25,
                windowDurationMinutes: 43_200,
                resetsAt: nil
            ),
            credits: nil,
            planType: "pro",
            ordinaryUsageAllowed: true,
            availableResetCredits: 0
        )
        let formatter = MenuBarTitleFormatter(language: .english)

        XCTAssertEqual(formatter.string(from: snapshot, mode: .compact), "mo 75%")
        XCTAssertEqual(formatter.string(from: snapshot, mode: .expanded), "mo 75%")
    }
}
