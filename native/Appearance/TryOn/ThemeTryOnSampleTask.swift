import SwiftUI

/// What Try On shows themes on when there's no task yet: a read-only task with a reply's code, a
/// diff and a test run, labelled as a sample. Nothing in it belongs to the user or reaches an agent.
struct ThemeTryOnSampleTask: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text(Self.prompt)
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextPrimary)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.md)
                    .background(.dsFill, in: .rect(cornerRadius: DS.Radius.message, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, DS.Space.xxxl * 2)
                MarkdownView(Self.reply)
                DiffView(path: "src/upload/chunker.ts", oldText: Self.before, newText: Self.after)
                MarkdownView(Self.testRun)
            }
            .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.vertical, DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(.dsBackground)
        .navigationTitle("Sample task")
        .navigationSubtitle("A sample for Try On. Nothing here is yours.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sample task")
    }

    private static let prompt =
        "Uploads fail for good when the connection drops mid-file. Retry each chunk with backoff, three tries, "
        + "and add a test that cuts the network halfway."

    private static let reply = """
        Only network errors should retry, and the wait should grow, so a flaky connection gets a chance \
        and a real `400` fails at once.

        ```ts
        export function backoff(tries: number, status = "503"): number {
          const base = status.startsWith("429") ? 2 : 1;
          return Math.min(base * 2 ** (tries - 1), 8); // seconds
        }
        ```
        """

    private static let before = """
        export async function sendChunk(chunk: Chunk): Promise<void> {
          const response = await fetch(chunk.url, { method: "PUT", body: chunk.data });
          if (!response.ok) throw new UploadError(response.status);
        }
        """

    private static let after = """
        export async function sendChunk(chunk: Chunk, tries = 1): Promise<void> {
          const response = await fetch(chunk.url, { method: "PUT", body: chunk.data });
          if (response.ok) return;
          if (tries >= 3 || response.status < 500) throw new UploadError(response.status);
          await sleep(backoff(tries, String(response.status)) * 1000);
          return sendChunk(chunk, tries + 1);
        }
        """

    private static let testRun = """
        ```sh
        pier ❯ bun test src/upload
        ✓ chunker > retries a chunk after the connection drops [41.20ms]
        ✓ chunker > gives up after three tries [12.08ms]
        ✓ upload > keeps the progress bar honest [8.31ms]

         14 pass
         0 fail
        ```

        Each chunk now retries up to three times on a network error, waiting 1, 2 and 4 seconds.
        """
}

#if DEBUG
#Preview("Try On - Sample task") {
    DSPreviewPair {
        ThemeTryOnSampleTask()
            .frame(width: 720, height: 640)
    }
}
#endif
