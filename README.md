# Restore Channel Post

Recover an accidentally deleted channel publication from **Recent Actions**, with its original message ID, publication date, time and position in the channel.

**Concept and submission:** [@standonzex](https://t.me/standonzex) · **Work channel:** [@zexeAI](https://t.me/zexeAI)

[Русская инструкция](README-RU.md) · [Implementation status](CODE-STATUS.md) · [Reviewer guide](submission/REVIEWER-EN.md)

## Feature flow

1. Long-press a channel post → Delete → Delete for Everyone.
2. Open channel profile → Edit → Recent Actions.
3. Long-press the deleted publication → Restore.
4. The existing original returns to its old place. No new post is sent.

Recovery is available within **48 hours of deletion**, including for publications originally posted years ago. Text, photographs and playable video messages use the same recovery path. The demo video is supplied separately with the submission; it uses a newer sample clip and autoplay capture mode. Source 1.8 retains the previous prepared clip. Physical camera/microphone capture is not implemented.

## Run on a Mac

Requires a Mac, Python 3 and Xcode Command Line Tools. The iPhone host additionally needs full Xcode and an iOS Simulator.

```sh
git clone https://github.com/standonzex/restore-channel-post.git
cd restore-channel-post
./build.sh
open 'dist/Restore Channel Post.app'
```

For iPhone Simulator:

```sh
./build-ios-demo.sh
./run-ios-demo.sh
```

The reference apps use their own authenticated local Python/SQLite service. No Telegram account, bot token or paid service is needed. Keep the iPhone launch terminal open while reviewing. See [iPhone setup](IOS-SETUP.md) and the [demo scenario](DEMO-SCENARIO.md).

## Integration scope

This is a **runnable reference implementation of a proposed Telegram feature**. It does not restore posts in live Telegram channels. A patch for Telegram iOS's existing Recent Actions screen is included, but the full patched Telegram client has not been built or run.

Deployment requires Telegram's canonical server restore operation, authenticated transport and normal update synchronization. Live reactions, discussion threads, search indexes and multi-client state require Telegram infrastructure work. See [integration notes](INTEGRATION.md) and [API contract](API-CONTRACT.md).

## Validation

The submitted 1.8 snapshot passed 64 automated behavior checks, Swift–HTTP–SQLite integration, standalone Mac/iPhone builds and signatures, and native patch application/source-consistency/syntax checks. Full upstream client compilation is not included in that claim. See [QA report](QA-REPORT.md). GitHub Actions results are separate from those recorded local checks.

```sh
./verify.sh
./build-ios-demo.sh
```

The original archive file hashes are recorded in [SOURCE-FILES.json](SOURCE-FILES.json). The GitHub landing-page documentation and author information are publication additions; runtime sources are the submitted version 1.8.

## Source layout

- `module/`: shared recovery coordinator and transport contract.
- `server/`: persistent canonical records, transactional recovery and local HTTP API.
- `app/`, `ios-demo/`: runnable reference hosts.
- `ios/`: Telegram-iOS patch and changed source files.
- `tests/`, `tools/`: behavior checks, builds and packaging.
- `submission/`: feature description and reviewer instructions.

Original-code and upstream-source terms are described in [LICENSE.md](LICENSE.md) and [NOTICE.md](NOTICE.md).
