import Foundation
import Git
import GitHub

/// The made-up task a preview runs on: one small change to a checkout page, seen as a request, a
/// diff, commits and a pull request, so every purpose previews against the same story.
enum AIInstructionSamples {
    static let projectName = "shop"
    static let request =
        "PAY-142: The checkout page charges twice when someone taps Pay twice. Disable the button while the payment is in flight, and add a test."
    static let title = "Prevent double charges at checkout"
    static let subjects = [
        "feat(checkout): add Apple Pay", "fix(cart): keep quantities after sign-in", "test(checkout): cover coupons",
        "refactor(payments): extract PaymentClient",
    ]

    static let files = [
        FileChange(
            path: "Sources/Checkout/PayButton.swift", kind: .modified, area: .unstaged,
            stats: LineStats(additions: 6, deletions: 1)),
        FileChange(
            path: "Tests/CheckoutTests/PayButtonTests.swift", kind: .modified, area: .unstaged,
            stats: LineStats(additions: 9)),
        FileChange(
            path: "docs/checkout.md", kind: .modified, area: .unstaged, stats: LineStats(additions: 2, deletions: 1)),
    ]

    static let patch = """
        diff --git a/Sources/Checkout/PayButton.swift b/Sources/Checkout/PayButton.swift
        --- a/Sources/Checkout/PayButton.swift
        +++ b/Sources/Checkout/PayButton.swift
        @@ -12,7 +12,12 @@ struct PayButton: View {
             var body: some View {
        -        Button("Pay \\(total)") { Task { await checkout.pay() } }
        +        Button("Pay \\(total)") {
        +            guard !isPaying else { return }
        +            isPaying = true
        +            Task { await checkout.pay(); isPaying = false }
        +        }
        +        .disabled(isPaying)
             }
        diff --git a/Tests/CheckoutTests/PayButtonTests.swift b/Tests/CheckoutTests/PayButtonTests.swift
        --- a/Tests/CheckoutTests/PayButtonTests.swift
        +++ b/Tests/CheckoutTests/PayButtonTests.swift
        @@ -30,3 +30,12 @@ final class PayButtonTests: XCTestCase {
        +    func testTappingTwiceChargesOnce() async {
        +        let checkout = FakeCheckout()
        +        let button = PayButton(checkout: checkout)
        +        button.tap()
        +        button.tap()
        +        await checkout.waitForPayments()
        +        XCTAssertEqual(checkout.charges, 1)
        +    }
        diff --git a/docs/checkout.md b/docs/checkout.md
        --- a/docs/checkout.md
        +++ b/docs/checkout.md
        @@ -8,1 +8,2 @@
        -Tapping Pay starts the payment.
        +Tapping Pay starts the payment. The button stays disabled until the payment
        +finishes, so a second tap can't charge twice.
        """

    static let commits = """
        a1b2c3d fix(checkout): disable Pay while a payment is in flight

        A second tap on Pay started a second payment before the first finished.
        """

    static let pullRequest = PullRequestReference(owner: "acme", name: "shop", number: 482)

    static var reviewRequest: ReviewAgentPrompt {
        ReviewAgentPrompt(
            reference: pullRequest, title: "Prevent double charges at checkout", branch: "fix-double-charge",
            anchor: ReviewAnchor(path: "Sources/Checkout/PayButton.swift", side: .right, line: 17, startLine: 14),
            excerpt: "+            guard !isPaying else { return }\n+            isPaying = true",
            notes: [.init(author: "reviewer", body: "Should this reset if the payment throws?")])
    }

    static var pullRequestSource: PullRequestAskSource {
        PullRequestAskSource(
            reference: pullRequest, title: "Prevent double charges at checkout", headRefName: "fix-double-charge",
            headRefOid: "a1b2c3d", body: "Disables Pay while a payment is in flight.", files: [])
    }

    static let question = "Is there any way this can still charge twice?"
}
