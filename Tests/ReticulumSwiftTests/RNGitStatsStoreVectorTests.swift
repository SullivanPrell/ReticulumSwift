//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation
import XCTest

@testable import ReticulumSwift

/// The stats file an `rngit` node keeps, as Python RNS 1.5.4 writes and reads it.
///
/// Every expectation is the figure the reference produced, and every byte string is what its
/// `umsgpack` packed. Python shares one dictionary across the groups it creates in a run
/// (`server.py:4810`); the sequences here were recorded with that dictionary copied per group,
/// which is what `STATS_INIT_GROUP` names.
final class RNGitStatsStoreVectorTests: XCTestCase {

  /// Each sequence of recorded events, with the figures and the file the reference made.
  private static let sequences:
    [(name: String, events: [[String]], statistics: RNGitStatistics, packed: String)] = [
      (
        "empty",
        [],
        RNGitStatistics(),
        "82a5706167657381a566726f6e7480a667726f75707380"
      ),
      (
        "one page view",
        [["page", "2026-09-13"]],
        RNGitStatistics(frontPageViews: ["2026-09-13": 1]),
        "82a5706167657381a566726f6e7481aa323032362d30392d313301a667726f75707380"
      ),
      (
        "page views two days",
        [["page", "2026-09-13"], ["page", "2026-09-13"], ["page", "2026-09-14"]],
        RNGitStatistics(frontPageViews: ["2026-09-13": 2, "2026-09-14": 1]),
        "82a5706167657381a566726f6e7482aa323032362d30392d313302aa323032362d30392d313401a667726f75707380"
      ),
      (
        "group view",
        [["group_view", "alpha", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(view: ["2026-09-13": 1])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380"
      ),
      (
        "group views repeat",
        [["group_view", "alpha", "2026-09-13"], ["group_view", "alpha", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(view: ["2026-09-13": 2])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657781aa323032362d30392d313302ac7265706f7369746f7269657380"
      ),
      (
        "two groups",
        [["group_view", "alpha", "2026-09-13"], ["group_view", "beta", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "beta": RNGitGroupStatistics(view: ["2026-09-13": 1]),
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707382a5616c70686182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a46265746182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380"
      ),
      (
        "two groups uneven",
        [
          ["group_view", "alpha", "2026-09-13"], ["group_view", "alpha", "2026-09-14"],
          ["group_view", "beta", "2026-09-13"],
        ],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(view: ["2026-09-13": 1, "2026-09-14": 1]),
            "beta": RNGitGroupStatistics(view: ["2026-09-13": 1]),
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707382a5616c70686182a47669657782aa323032362d30392d313301aa323032362d30392d313401ac7265706f7369746f7269657380a46265746182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380"
      ),
      (
        "repo view",
        [["view", "alpha", "repo", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "repo view creates group",
        [["view", "alpha", "repo", "2026-09-13"], ["group_view", "alpha", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(
              view: ["2026-09-13": 1],
              repositories: [
                "repo": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
              ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657381a47265706f85a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "two repos one group",
        [["view", "alpha", "one", "2026-09-13"], ["view", "alpha", "two", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "one": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "two": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657382a36f6e6585a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a374776f85a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "same repo two groups",
        [
          ["view", "alpha", "repo", "2026-09-13"], ["view", "beta", "repo", "2026-09-13"],
          ["view", "beta", "repo", "2026-09-13"],
        ],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
            ]),
            "beta": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(view: ["2026-09-13": 2])
            ]),
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707382a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a46265746182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657781aa323032362d30392d313302a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "fetch",
        [["fetch", "alpha", "repo", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(fetch: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657780a5666574636881aa323032362d30392d313301a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "push",
        [["push", "alpha", "repo", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(push: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657780a5666574636880a47075736881aa323032362d30392d313301a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "download",
        [["download", "alpha", "repo", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(download: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657780a5666574636880a47075736880a8646f776e6c6f616481aa323032362d30392d313301b072656c656173655f646f776e6c6f616480"
      ),
      (
        "release download",
        [["release_download", "alpha", "repo", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "repo": RNGitRepositoryStatistics(releaseDownload: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f7269657381a47265706f85a47669657780a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616481aa323032362d30392d313301"
      ),
      (
        "every counter",
        [
          ["view", "a", "r", "2026-09-13"], ["fetch", "a", "r", "2026-09-13"],
          ["push", "a", "r", "2026-09-13"], ["download", "a", "r", "2026-09-13"],
          ["release_download", "a", "r", "2026-09-13"],
        ],
        RNGitStatistics(
          groups: [
            "a": RNGitGroupStatistics(repositories: [
              "r": RNGitRepositoryStatistics(
                view: ["2026-09-13": 1], fetch: ["2026-09-13": 1], push: ["2026-09-13": 1],
                download: ["2026-09-13": 1], releaseDownload: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a16182a47669657780ac7265706f7369746f7269657381a17285a47669657781aa323032362d30392d313301a5666574636881aa323032362d30392d313301a47075736881aa323032362d30392d313301a8646f776e6c6f616481aa323032362d30392d313301b072656c656173655f646f776e6c6f616481aa323032362d30392d313301"
      ),
      (
        "mixed",
        [
          ["page", "2026-09-13"], ["group_view", "a", "2026-09-13"],
          ["view", "a", "r", "2026-09-13"], ["fetch", "a", "r", "2026-09-14"],
          ["fetch", "a", "r", "2026-09-14"], ["push", "b", "s", "2025-01-01"],
          ["page", "2026-09-14"], ["group_view", "b", "2025-01-01"],
        ],
        RNGitStatistics(
          frontPageViews: ["2026-09-13": 1, "2026-09-14": 1],
          groups: [
            "a": RNGitGroupStatistics(
              view: ["2026-09-13": 1],
              repositories: [
                "r": RNGitRepositoryStatistics(view: ["2026-09-13": 1], fetch: ["2026-09-14": 2])
              ]),
            "b": RNGitGroupStatistics(
              view: ["2025-01-01": 1],
              repositories: [
                "s": RNGitRepositoryStatistics(push: ["2025-01-01": 1])
              ]),
          ]
        ),
        "82a5706167657381a566726f6e7482aa323032362d30392d313301aa323032362d30392d313401a667726f75707382a16182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657381a17285a47669657781aa323032362d30392d313301a5666574636881aa323032362d30392d313402a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a16282a47669657781aa323032352d30312d303101ac7265706f7369746f7269657381a17385a47669657780a5666574636880a47075736881aa323032352d30312d303101a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "unicode names",
        [["view", "gr\u{FC}ppe", "repo\u{2014}one", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "gr\u{FC}ppe": RNGitGroupStatistics(repositories: [
              "repo\u{2014}one": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a76772c3bc70706582a47669657780ac7265706f7369746f7269657381aa7265706fe280946f6e6585a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "empty names",
        [["view", "", "", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "": RNGitGroupStatistics(repositories: [
              "": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a082a47669657780ac7265706f7369746f7269657381a085a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "dotted names",
        [["view", "a.b", "c.d", "2026-09-13"]],
        RNGitStatistics(
          groups: [
            "a.b": RNGitGroupStatistics(repositories: [
              "c.d": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a3612e6282a47669657780ac7265706f7369746f7269657381a3632e6485a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
      (
        "old day",
        [["page", "2025-01-01"], ["page", "2026-09-13"]],
        RNGitStatistics(frontPageViews: ["2025-01-01": 1, "2026-09-13": 1]),
        "82a5706167657381a566726f6e7482aa323032352d30312d303101aa323032362d30392d313301a667726f75707380"
      ),
      (
        "many days",
        [
          ["page", "2026-09-01"], ["page", "2026-09-02"], ["page", "2026-09-03"],
          ["page", "2026-09-04"], ["page", "2026-09-05"], ["page", "2026-09-06"],
          ["page", "2026-09-07"], ["page", "2026-09-08"], ["page", "2026-09-09"],
          ["page", "2026-09-10"], ["page", "2026-09-11"], ["page", "2026-09-12"],
          ["page", "2026-09-13"], ["page", "2026-09-14"],
        ],
        RNGitStatistics(
          frontPageViews: [
            "2026-09-01": 1, "2026-09-02": 1, "2026-09-03": 1, "2026-09-04": 1, "2026-09-05": 1,
            "2026-09-06": 1, "2026-09-07": 1, "2026-09-08": 1, "2026-09-09": 1, "2026-09-10": 1,
            "2026-09-11": 1, "2026-09-12": 1, "2026-09-13": 1, "2026-09-14": 1,
          ]
        ),
        "82a5706167657381a566726f6e748eaa323032362d30392d303101aa323032362d30392d303201aa323032362d30392d303301aa323032362d30392d303401aa323032362d30392d303501aa323032362d30392d303601aa323032362d30392d303701aa323032362d30392d303801aa323032362d30392d303901aa323032362d30392d313001aa323032362d30392d313101aa323032362d30392d313201aa323032362d30392d313301aa323032362d30392d313401a667726f75707380"
      ),
      (
        "many groups",
        [
          ["group_view", "zulu", "2026-09-13"], ["group_view", "yankee", "2026-09-13"],
          ["group_view", "xray", "2026-09-13"], ["group_view", "whiskey", "2026-09-13"],
          ["group_view", "victor", "2026-09-13"], ["group_view", "uniform", "2026-09-13"],
          ["group_view", "tango", "2026-09-13"], ["group_view", "sierra", "2026-09-13"],
        ],
        RNGitStatistics(
          groups: [
            "sierra": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "tango": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "uniform": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "victor": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "whiskey": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "xray": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "yankee": RNGitGroupStatistics(view: ["2026-09-13": 1]),
            "zulu": RNGitGroupStatistics(view: ["2026-09-13": 1]),
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707388a673696572726182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a574616e676f82a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a7756e69666f726d82a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a6766963746f7282a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a7776869736b657982a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a47872617982a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a679616e6b656582a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380a47a756c7582a47669657781aa323032362d30392d313301ac7265706f7369746f7269657380"
      ),
      (
        "many repositories",
        [
          ["view", "alpha", "r12", "2026-09-13"], ["view", "alpha", "r11", "2026-09-13"],
          ["view", "alpha", "r10", "2026-09-13"], ["view", "alpha", "r9", "2026-09-13"],
          ["view", "alpha", "r8", "2026-09-13"], ["view", "alpha", "r7", "2026-09-13"],
          ["view", "alpha", "r6", "2026-09-13"], ["view", "alpha", "r5", "2026-09-13"],
          ["view", "alpha", "r4", "2026-09-13"], ["view", "alpha", "r3", "2026-09-13"],
          ["view", "alpha", "r2", "2026-09-13"], ["view", "alpha", "r1", "2026-09-13"],
        ],
        RNGitStatistics(
          groups: [
            "alpha": RNGitGroupStatistics(repositories: [
              "r1": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r10": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r11": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r12": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r2": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r3": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r4": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r5": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r6": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r7": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r8": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
              "r9": RNGitRepositoryStatistics(view: ["2026-09-13": 1]),
            ])
          ]
        ),
        "82a5706167657381a566726f6e7480a667726f75707381a5616c70686182a47669657780ac7265706f7369746f726965738ca2723185a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a372313085a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a372313185a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a372313285a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723285a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723385a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723485a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723585a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723685a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723785a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723885a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480a2723985a47669657781aa323032362d30392d313301a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480"
      ),
    ]

  /// Each stats file the reference could read, with the figures it took from it.
  private static let files: [(name: String, packed: String, statistics: RNGitStatistics)] = [
    ("default", "82a5706167657381a566726f6e7480a667726f75707380", RNGitStatistics()),
    ("shuffled keys", "82a667726f75707380a5706167657381a566726f6e7480", RNGitStatistics()),
    (
      "populated",
      "82a5706167657381a566726f6e7481aa323032362d30392d313303a667726f75707381a16182a47669657781aa323032362d30392d313301ac7265706f7369746f7269657381a17285a47669657781aa323032362d30392d313302a5666574636880a47075736880a8646f776e6c6f616480b072656c656173655f646f776e6c6f616480",
      RNGitStatistics(
        frontPageViews: ["2026-09-13": 3],
        groups: [
          "a": RNGitGroupStatistics(
            view: ["2026-09-13": 1],
            repositories: [
              "r": RNGitRepositoryStatistics(view: ["2026-09-13": 2])
            ])
        ]
      )
    ),
    ("missing pages", "81a667726f75707380", RNGitStatistics()),
    (
      "missing groups", "81a5706167657381a566726f6e7481aa323032362d30392d313301",
      RNGitStatistics(frontPageViews: ["2026-09-13": 1])
    ),
    ("missing front", "82a5706167657380a667726f75707380", RNGitStatistics()),
    (
      "extra top key", "83a5706167657381a566726f6e7480a667726f75707380a5657874726101",
      RNGitStatistics()
    ),
    (
      "extra page key",
      "82a5706167657382a566726f6e7480a46261636b81aa323032362d30392d313305a667726f75707380",
      RNGitStatistics()
    ),
    (
      "extra group key",
      "82a5706167657381a566726f6e7480a667726f75707381a16183a47669657780ac7265706f7369746f7269657380a17801",
      RNGitStatistics(
        groups: [
          "a": RNGitGroupStatistics()
        ]
      )
    ),
    (
      "group missing view",
      "82a5706167657381a566726f6e7480a667726f75707381a16181ac7265706f7369746f7269657380",
      RNGitStatistics(
        groups: [
          "a": RNGitGroupStatistics()
        ]
      )
    ),
    (
      "group missing repositories",
      "82a5706167657381a566726f6e7480a667726f75707381a16181a47669657781aa323032362d30392d313301",
      RNGitStatistics(
        groups: [
          "a": RNGitGroupStatistics(view: ["2026-09-13": 1])
        ]
      )
    ),
    (
      "repo missing counters",
      "82a5706167657381a566726f6e7480a667726f75707381a16182a47669657780ac7265706f7369746f7269657381a17281a47669657781aa323032362d30392d313301",
      RNGitStatistics(
        groups: [
          "a": RNGitGroupStatistics(repositories: [
            "r": RNGitRepositoryStatistics(view: ["2026-09-13": 1])
          ])
        ]
      )
    ),
    (
      "string count", "82a5706167657381a566726f6e7481aa323032362d30392d3133a133a667726f75707380",
      RNGitStatistics()
    ),
    (
      "bool count", "82a5706167657381a566726f6e7481aa323032362d30392d3133c3a667726f75707380",
      RNGitStatistics()
    ),
    (
      "float count",
      "82a5706167657381a566726f6e7481aa323032362d30392d3133cb3ff8000000000000a667726f75707380",
      RNGitStatistics()
    ),
    (
      "negative count", "82a5706167657381a566726f6e7481aa323032362d30392d3133fea667726f75707380",
      RNGitStatistics(frontPageViews: ["2026-09-13": -2])
    ),
    (
      "zero count", "82a5706167657381a566726f6e7481aa323032362d30392d313300a667726f75707380",
      RNGitStatistics(frontPageViews: ["2026-09-13": 0])
    ),
    (
      "large count",
      "82a5706167657381a566726f6e7481aa323032362d30392d3133cf0000000200000000a667726f75707380",
      RNGitStatistics(frontPageViews: ["2026-09-13": 8_589_934_592])
    ),
    ("null group", "82a5706167657381a566726f6e7480a667726f75707381a161c0", RNGitStatistics()),
    ("list group", "82a5706167657381a566726f6e7480a667726f75707381a16190", RNGitStatistics()),
    (
      "null counters",
      "82a5706167657381a566726f6e7480a667726f75707381a16182a476696577c0ac7265706f7369746f7269657381a172c0",
      RNGitStatistics(
        groups: [
          "a": RNGitGroupStatistics()
        ]
      )
    ),
    ("pages not a map", "82a5706167657305a667726f75707380", RNGitStatistics()),
    ("groups not a map", "82a5706167657381a566726f6e7480a667726f75707305", RNGitStatistics()),
    ("front not a map", "82a5706167657381a566726f6e7405a667726f75707380", RNGitStatistics()),
    ("empty map", "80", RNGitStatistics()),
  ]

  /// Each stats file that is not a map, which leaves the node with empty figures.
  private static let unreadable: [(name: String, packed: String)] = [
    ("empty file", ""),
    ("one byte", "82"),
    ("integer payload", "05"),
    ("string payload", "a46e6f7065"),
    ("list payload", "920102"),
    ("nil payload", "c0"),
    ("truncated map", "82a570"),
  ]

  /// The file a node writes when it finds no stats file, per `server.py:2079-2081`.
  private static let emptyFile = "82a5706167657381a566726f6e7480a667726f75707380"

  /// Every recorded sequence yields the reference's figures and its file.
  func testRecordedSequencesMatchTheReference() {
    for vector in Self.sequences {
      var statistics = RNGitStatistics()
      for event in vector.events { Self.apply(event, to: &statistics) }
      XCTAssertEqual(statistics, vector.statistics, vector.name)
      XCTAssertEqual(statistics.encoded().hexString, vector.packed, vector.name)
      XCTAssertEqual(RNGitStatistics.decoding(statistics.encoded()), statistics, vector.name)
    }
  }

  /// Every stats file the reference wrote reads back as the figures it held.
  func testStoredFilesMatchTheReference() throws {
    for vector in Self.files {
      let data = try XCTUnwrap(Data(pythonHex: vector.packed), vector.name)
      XCTAssertEqual(RNGitStatistics.decoding(data), vector.statistics, vector.name)
    }
  }

  /// A file that is not a stats map leaves the node with empty figures.
  func testUnreadableFilesYieldEmptyStatistics() {
    for vector in Self.unreadable {
      let data = Data(pythonHex: vector.packed) ?? Data()
      XCTAssertEqual(RNGitStatistics.decoding(data), RNGitStatistics(), vector.name)
    }
  }

  /// A missing stats file is created holding empty figures, and persisting replaces it.
  func testStoreCreatesAndReplacesTheFile() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("stats").path

    XCTAssertEqual(RNGitStatsStore.load(from: path), RNGitStatistics())
    let created = try XCTUnwrap(FileManager.default.contents(atPath: path))
    XCTAssertEqual(created.hexString, Self.emptyFile)

    var statistics = RNGitStatistics()
    statistics.recordPageView(on: "2026-09-13")
    statistics.recordFetch("alpha", "repo", on: "2026-09-13")
    try RNGitStatsStore.persist(statistics, to: path)
    XCTAssertEqual(RNGitStatsStore.load(from: path), statistics)
    XCTAssertFalse(FileManager.default.fileExists(atPath: path + ".tmp"))
  }

  /// Persisting replaces a stats path that is a symbolic link, leaving its target alone.
  ///
  /// Python renames the temporary file over the path (`server.py:2094`), which replaces the
  /// link itself rather than writing through it.
  func testPersistReplacesASymbolicLink() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("target")
    let path = directory.appendingPathComponent("stats").path
    try Data("original".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "target")

    try RNGitStatsStore.persist(RNGitStatistics(), to: path)

    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
    XCTAssertEqual(try Data(contentsOf: target), Data("original".utf8))
    XCTAssertEqual(
      try XCTUnwrap(FileManager.default.contents(atPath: path)).hexString,
      "82a5706167657381a566726f6e7480a667726f75707380")
    XCTAssertEqual(FileManager.default.fileExists(atPath: path + ".tmp"), false)
  }

  /// The day key is the local calendar date, as `_get_day` formats it.
  func testDayKeyIsTheLocalDate() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    XCTAssertEqual(
      RNGitStatsStore.day(at: Date(timeIntervalSince1970: 0)),
      formatter.string(from: Date(timeIntervalSince1970: 0)))
  }

  private static func apply(_ event: [String], to statistics: inout RNGitStatistics) {
    switch event[0] {
    case "page": statistics.recordPageView(on: event[1])
    case "group_view": statistics.recordGroupView(event[1], on: event[2])
    case "view": statistics.recordRepositoryView(event[1], event[2], on: event[3])
    case "fetch": statistics.recordFetch(event[1], event[2], on: event[3])
    case "push": statistics.recordPush(event[1], event[2], on: event[3])
    case "download": statistics.recordDownload(event[1], event[2], on: event[3])
    case "release_download": statistics.recordReleaseDownload(event[1], event[2], on: event[3])
    default: XCTFail("unknown event \(event[0])")
    }
  }
}
