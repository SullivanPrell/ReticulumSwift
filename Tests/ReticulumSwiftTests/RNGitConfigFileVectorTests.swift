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

/// Configurations read by `configobj` as Python RNS 1.5.4 vendors it.
///
/// The corpus holds the node's own default configuration alongside the quoting, comment,
/// list and nesting cases that decide how a line is read, and the three errors the parser
/// raises.
final class RNGitConfigFileVectorTests: XCTestCase {

  /// Each configuration with the sections and values the reference read from it.
  private static let files: [(name: String, text: String, config: RNGitConfigSection)] = [
    (
      "default",
      "# This is the default rngit config file.\n# You will need to edit it to specify rep"
        + "ository locations and\n# access permissions.\n\n[rngit]\n\n# Automatic announce int"
        + "erval in minutes.\n# 6 hours by default.\n\nannounce_interval = 360\n\n# An optiona"
        + "l name for this node, included\n# in announces.\n\n# node_name = Anonymous Git Node"
        + "\n\n# You can enable collecting view, fetch and push statistics\n# which can be dis"
        + "played on the stats pages of repositories.\n# Remember to set the \"s\" (stats) per"
        + "mission appropriately\n# for statistics to actually be viewable by anyone.\n\n# rec"
        + "ord_stats = no\n# stats_ignore_identities = 9710b86ba12c42d1d8f30f74fe509286\n# sta"
        + "ts_push_ignore_identities = 5bffebe038654304dafcbe12cbcd0412\n\n# You can block spe"
        + "cific identities from any interaction\n# with this node.\n\n# blocked_identities = "
        + "d31aeea49873006f13b3415520666a4e\n\n# To make it easier to handle scrapers, crawler"
        + "s, slopware\n# and other annoyances, you can block unidentified peers by\n# adding "
        + "the null_ident hash to to blocked identities.\n\n# blocked_identities = d7db22f63b4"
        + "53c23bb0688dde565b7c1\n\n[repositories]\n\n# You can define multiple repository gro"
        + "ups, each with a path\n# to the directory containing \"repo_name.git\" directories."
        + "\n\ninternal = /path/to/directory/with/git/repositories\npublic = /another/path/to/"
        + "directory/with/git/repositories\nshowcase = /another/path/to/directory/with/git/rep"
        + "ositories\n\n# To add a short description to your repositories, you can\n# either p"
        + "lace a \"repo_name.description\" file in the same\n# directory as the repository fo"
        + "lder, or set it in the bare\n# repository with `git config repository.description`."
        + "\n\n# If you have mirrored repositories with the \"rngit mirror\"\n# command, you c"
        + "an configure the global mirroring interval\n# in hours.\n\n# mirror_interval = 24\n"
        + "\n\n[aliases]\n\n# You can define aliases for commonly used identity hashes\n# in t"
        + "his section. Each line must be in the format\n# aliased_name = IDENTITY_HASH\n#\n# "
        + "These hashes are used for the permissions system and\n# identity resolution. For rn"
        + "git CLI client operations,\n# aliases must be defined in ~/.rngit/client_config.\n"
        + "\n# alice = d09285e660cfe27cee6d9a0beb58b7e0\n# bob = ffcffb4e255e156e77f79b82c1308"
        + "6a6\n\n[access]\n\n# You can apply permissions for all repositories within\n# diffe"
        + "rent repository collections like this:\n\npublic = r:all, w:9710b86ba12c42d1d8f30f7"
        + "4fe509286\ninternal = rw:9710b86ba12c42d1d8f30f74fe509286\n\n# By default, all repo"
        + "sitories sourced from the con-\n# figured repository collection paths have no permi"
        + "ssions\n# enabled, and will be neither readable nor writable.\n#\n# The following p"
        + "ermissions are supported:\n#   r   = read       (clone, fetch, view)\n#   w   = wri"
        + "te      (push, create and manage work documents)\n#   rw  = read/write\n#   c   = c"
        + "reate     (create new repositories in group)\n#   s   = stats      (view repository"
        + " statistics)\n#   rel = release    (create and manage releases)\n#   i   = interact"
        + "   (comment on work documents)\n#   p   = propose    (propose new work documents)\n"
        + "#   adm = admin      (full administrative access)\n#\n# To configure permissions pe"
        + "r repository, you must create\n# an \".allowed\" file matching the repository name."
        + " If the\n# repository is in a folder called \"my_project.git\", create\n# a \"my_pr"
        + "oject.allowed\" file next to it. This file must\n# contain a permission statement o"
        + "n each line in the form of\n# \"r:IDENTITY_HASH\", \"w:IDENTITY_HASH\" or \"r:IDENT"
        + "ITY_HASH\".\n# Instead of IDENTITY_HASH, you can also use \"all\" or \"none\".\n#\n"
        + "# You can also make the allow-files executable, and have them\n# evaluate or source"
        + " the permissions from somewhere else,\n# and then output the results to stdout.\n#"
        + "\n# Additionally, you can create a \"group.allowed\" file in the\n# root of a repos"
        + "itory group directory, which will apply to\n# all repositories within this group. T"
        + "he same syntax and\n# functionality applies here.\n\n\n[pages]\n# You can run a nom"
        + "adnet-compatible page node to serve\n# repository information if required. Access p"
        + "ermissions\n# will follow those configured per group and repository.\n#\n# The page"
        + " server supports automatic markdown to micron\n# conversion for repository readmes "
        + "and other files. If\n# you have the pygments Python module installed, syntax\n# hig"
        + "hlighting will also be automatically applied.\n#\n# The page server is highly custo"
        + "mizable, and you can\n# provide custom templates for each page type by placing\n# a"
        + " corresponding \"template_name.mu\" file in the\n# ~/.rngit/templates directory. Th"
        + "e supported template\n# names are \"base\", \"front\", \"group\", \"repo\", \"tree"
        + "\",\n# \"blob\", \"commits\", \"commit\", \"refs\", \"stats\", \"releases\",\n# \"r"
        + "elease\", \"work\" and \"work_doc\". You should include a\n# {PAGE_CONTENT} variabl"
        + "e somewhere in your templates,\n# the rendered page content will be injected into t"
        + "his\n# variable.\n\n# serve_nomadnet = no\n\n# It is possible to disable Nerd Font "
        + "icons and instead\n# use simpler (but more compatible) unicode icons.\n\n# unicode_"
        + "icons = yes\n\n# You can configure whether the page server should try\n# to convert"
        + " media files to WebP on the fly, for serving\n# to nomadnet clients. Enabled by def"
        + "ault, but will\n# require an available encoding backend installed on\n# your system"
        + ". Supported backends utilities are \"magick\",\n# \"convert\", \"gm\", \"ffmpeg\" a"
        + "nd \"avconv\". If any one is\n# installed, rngit will auto-detect and use it, but y"
        + "ou\n# can force a specific backend with the environment\n# variable RNGIT_MEDIA_BAC"
        + "KEND.\n\n# media_conversion = yes\n\n\n[logging]\n# Valid log levels are 0 through "
        + "8:\n#   0: Log only critical information\n#   1: Log errors and lower log levels\n#"
        + "   2: Log warnings and lower log levels\n#   3: Log notices and lower log levels\n#"
        + "   4: Log info and lower (this is the default)\n#   5: Verbose logging\n#   6: Debu"
        + "g logging\n#   7: Pathing logging\n#   8: Extreme logging\n\nloglevel = 4\n",
      RNGitConfigSection([
        (
          "rngit",
          .section(
            RNGitConfigSection([
              ("announce_interval", .scalar("360"))
            ]))
        ),
        (
          "repositories",
          .section(
            RNGitConfigSection([
              ("internal", .scalar("/path/to/directory/with/git/repositories")),
              ("public", .scalar("/another/path/to/directory/with/git/repositories")),
              ("showcase", .scalar("/another/path/to/directory/with/git/repositories")),
            ]))
        ),
        ("aliases", .section(RNGitConfigSection([]))),
        (
          "access",
          .section(
            RNGitConfigSection([
              ("public", .list(["r:all", "w:9710b86ba12c42d1d8f30f74fe509286"])),
              ("internal", .scalar("rw:9710b86ba12c42d1d8f30f74fe509286")),
            ]))
        ),
        ("pages", .section(RNGitConfigSection([]))),
        (
          "logging",
          .section(
            RNGitConfigSection([
              ("loglevel", .scalar("4"))
            ]))
        ),
      ])
    ),
    (
      "empty", "",
      RNGitConfigSection([])
    ),
    (
      "comments only", "# one\n\n  # two\n",
      RNGitConfigSection([])
    ),
    (
      "root keys", "k = v\nj = w\n",
      RNGitConfigSection([
        ("k", .scalar("v")),
        ("j", .scalar("w")),
      ])
    ),
    (
      "one section", "[a]\nk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "two sections", "[a]\nk = v\n[b]\nk = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        ),
        (
          "b",
          .section(
            RNGitConfigSection([
              ("k", .scalar("w"))
            ]))
        ),
      ])
    ),
    (
      "nested", "[a]\n[[b]]\nk = v\n[[[c]]]\nj = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (
                "b",
                .section(
                  RNGitConfigSection([
                    ("k", .scalar("v")),
                    (
                      "c",
                      .section(
                        RNGitConfigSection([
                          ("j", .scalar("w"))
                        ]))
                    ),
                  ]))
              )
            ]))
        )
      ])
    ),
    (
      "nested back", "[a]\n[[b]]\nk = v\n[c]\nj = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (
                "b",
                .section(
                  RNGitConfigSection([
                    ("k", .scalar("v"))
                  ]))
              )
            ]))
        ),
        (
          "c",
          .section(
            RNGitConfigSection([
              ("j", .scalar("w"))
            ]))
        ),
      ])
    ),
    (
      "indented", "[a]\n    k = v\n  [[b]]\n      j = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v")),
              (
                "b",
                .section(
                  RNGitConfigSection([
                    ("j", .scalar("w"))
                  ]))
              ),
            ]))
        )
      ])
    ),
    (
      "quoted section", "[\"a b\"]\nk = v\n",
      RNGitConfigSection([
        (
          "a b",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "section comment", "[a] # hi\nk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "section spaces", "[  a  ]\nk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "quoted key", "[a]\n\"my key\" = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("my key", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "key spaces", "[a]\nmy key = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("my key", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "key equals in value", "[a]\nk = x=y\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("x=y"))
            ]))
        )
      ])
    ),
    (
      "empty value", "[a]\nk =\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "value spaces", "[a]\nk =    v   \n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "value tabs", "[a]\nk =\tv\t\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "inline comment", "[a]\nk = v # hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "hash no space", "[a]\nk = v# hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "hash in double", "[a]\nk = \"v # hi\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v # hi"))
            ]))
        )
      ])
    ),
    (
      "hash in single", "[a]\nk = 'v # hi'\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v # hi"))
            ]))
        )
      ])
    ),
    (
      "double quoted", "[a]\nk = \"v\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "single quoted", "[a]\nk = 'v'\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "quoted comma", "[a]\nk = \"x, y\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("x, y"))
            ]))
        )
      ])
    ),
    (
      "list", "[a]\nk = x, y, z\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x", "y", "z"]))
            ]))
        )
      ])
    ),
    (
      "list spaces", "[a]\nk =  x ,  y  ,z \n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x", "y", "z"]))
            ]))
        )
      ])
    ),
    (
      "list trailing comma", "[a]\nk = x,\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x"]))
            ]))
        )
      ])
    ),
    (
      "single comma", "[a]\nk = ,\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list([]))
            ]))
        )
      ])
    ),
    (
      "list quoted items", "[a]\nk = \"x, y\", z\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x, y", "z"]))
            ]))
        )
      ])
    ),
    (
      "list with comment", "[a]\nk = x, y # hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x", "y"]))
            ]))
        )
      ])
    ),
    (
      "colon value", "[a]\nk = r:all\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("r:all"))
            ]))
        )
      ])
    ),
    (
      "colon list", "[a]\nk = r:all, w:none\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["r:all", "w:none"]))
            ]))
        )
      ])
    ),
    (
      "path value", "[a]\nk = ~/some/path\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("~/some/path"))
            ]))
        )
      ])
    ),
    (
      "path with space", "[a]\nk = /some path/here\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("/some path/here"))
            ]))
        )
      ])
    ),
    (
      "triple one line", "[a]\nk = \"\"\"v\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "triple multiline", "[a]\nk = \"\"\"one\ntwo\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("one\ntwo"))
            ]))
        )
      ])
    ),
    (
      "triple single", "[a]\nk = '''one\ntwo'''\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("one\ntwo"))
            ]))
        )
      ])
    ),
    (
      "triple comment", "[a]\nk = \"\"\"v\"\"\" # hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "crlf", "[a]\r\nk = v\r\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "blank lines", "\n\n[a]\n\n\nk = v\n\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "no key", "[a]\n = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (" ", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "deep siblings", "[a]\n[[b]]\nk = v\n[[c]]\nj = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (
                "b",
                .section(
                  RNGitConfigSection([
                    ("k", .scalar("v"))
                  ]))
              ),
              (
                "c",
                .section(
                  RNGitConfigSection([
                    ("j", .scalar("w"))
                  ]))
              ),
            ]))
        )
      ])
    ),
    (
      "deep then root", "[a]\n[[b]]\n[[[c]]]\nk = v\n[d]\nj = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (
                "b",
                .section(
                  RNGitConfigSection([
                    (
                      "c",
                      .section(
                        RNGitConfigSection([
                          ("k", .scalar("v"))
                        ]))
                    )
                  ]))
              )
            ]))
        ),
        (
          "d",
          .section(
            RNGitConfigSection([
              ("j", .scalar("w"))
            ]))
        ),
      ])
    ),
    (
      "same name nested", "[a]\n[[a]]\nk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              (
                "a",
                .section(
                  RNGitConfigSection([
                    ("k", .scalar("v"))
                  ]))
              )
            ]))
        )
      ])
    ),
    (
      "hash in triple", "[a]\nk = \"\"\"v # hi\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v # hi"))
            ]))
        )
      ])
    ),
    (
      "comma in triple", "[a]\nk = \"\"\"x, y\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("x, y"))
            ]))
        )
      ])
    ),
    (
      "triple three lines", "[a]\nk = \"\"\"one\ntwo\nthree\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("one\ntwo\nthree"))
            ]))
        )
      ])
    ),
    (
      "triple empty", "[a]\nk = \"\"\"\"\"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "empty double", "[a]\nk = \"\"\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "empty single", "[a]\nk = ''\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "list empty item", "[a]\nk = x, \"\", y\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x", "", "y"]))
            ]))
        )
      ])
    ),
    (
      "list trailing comment", "[a]\nk = x, y, # hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["x", "y"]))
            ]))
        )
      ])
    ),
    (
      "quoted hash item", "[a]\nk = \"a#b\", c\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["a#b", "c"]))
            ]))
        )
      ])
    ),
    (
      "value starts hash", "[a]\nk = #hi\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "value one quote", "[a]\nk = a\"b\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("a\"b"))
            ]))
        )
      ])
    ),
    (
      "key quoted equals", "[a]\n\"k=j\" = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k=j", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "key hash", "[a]\nk#j = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k#j", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "section unquoted quote", "[a\"b]\nk = v\n",
      RNGitConfigSection([
        (
          "a\"b",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "tab indent", "[a]\n\tk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("v"))
            ]))
        )
      ])
    ),
    (
      "root then section", "k = v\n[a]\nj = w\n",
      RNGitConfigSection([
        ("k", .scalar("v")),
        (
          "a",
          .section(
            RNGitConfigSection([
              ("j", .scalar("w"))
            ]))
        ),
      ])
    ),
    (
      "value only spaces", "[a]\nk =    \n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar(""))
            ]))
        )
      ])
    ),
    (
      "list unbalanced double", "[a]\nk = a, \"a,\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["a", "\"a"]))
            ]))
        )
      ])
    ),
    (
      "list unbalanced single", "[a]\nk = a, 'a,\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["a", "'a"]))
            ]))
        )
      ])
    ),
    (
      "list mixed quotes", "[a]\nk = \"\",'\",\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["", "'\""]))
            ]))
        )
      ])
    ),
    (
      "list quote inside", "[a]\nk = a\", \"a,\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .list(["a\"", "\"a"]))
            ]))
        )
      ])
    ),
    (
      "drop then descend", "[a]\n[[b]]\n[c]\n[[d]]\nk = v\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("b", .section(RNGitConfigSection([])))
            ]))
        ),
        (
          "c",
          .section(
            RNGitConfigSection([
              (
                "d",
                .section(
                  RNGitConfigSection([
                    ("k", .scalar("v"))
                  ]))
              )
            ]))
        ),
      ])
    ),
    (
      "triple closes later", "[a]\nk = \"\"\"one\ntwo\"\"\"\nj = w\n",
      RNGitConfigSection([
        (
          "a",
          .section(
            RNGitConfigSection([
              ("k", .scalar("one\ntwo")),
              ("j", .scalar("w")),
            ]))
        )
      ])
    ),
  ]

  /// Each configuration the reference refused, with the first error it raised.
  private static let refused: [(name: String, text: String, error: RNGitConfigError)] = [
    ("bracket mismatch", "[[a]\nk = v\n", .nesting(line: 1)),
    ("too nested", "[a]\n[[[b]]]\nk = v\n", .nesting(line: 2)),
    ("duplicate section", "[a]\nk = v\n[a]\nj = w\n", .duplicate(line: 3)),
    ("duplicate key", "[a]\nk = 1\nk = 2\n", .duplicate(line: 3)),
    ("no equals", "[a]\nbare line\n", .parse(line: 2)),
    ("double comma", "[a]\nk = x,,y\n", .parse(line: 2)),
    ("leading comma", "[a]\nk = ,x\n", .parse(line: 2)),
    ("unbalanced quote", "[a]\nk = \"v\n", .parse(line: 2)),
    ("triple unterminated", "[a]\nk = \"\"\"one\ntwo\n", .parse(line: 2)),
    ("bom", "\u{FEFF}[a]\nk = v\n", .parse(line: 1)),
    ("empty section", "[]\nk = v\n", .parse(line: 1)),
    ("space section", "[ ]\nk = v\n", .parse(line: 1)),
    ("key then section", "[a]\nk = v\n[[k]]\nj = w\n", .duplicate(line: 3)),
    ("bracket mismatch nested", "[a]\n[[b]\nk = v\n", .nesting(line: 2)),
    ("bracket extra close", "[a]]\nk = v\n", .nesting(line: 1)),
    ("drop then too nested", "[a]\n[[b]]\n[[[c]]]\n[d]\n[[[e]]]\nk = v\n", .nesting(line: 5)),
    ("triple trailing text", "[a]\nk = \"\"\"a\"\"\"b\n", .parse(line: 2)),
    ("triple trailing then close", "[a]\nk = \"\"\"a\"\"\"b\nc\"\"\"\nj = w\n", .parse(line: 2)),
    ("equals key", "[a]\n=k = v\n", .parse(line: 2)),
    ("equals twice", "[a]\n= a = b\n", .parse(line: 2)),
    ("quoted empty section", "[\"\"]\nk = v\n", .parse(line: 1)),
    ("quoted space section", "[\"  \"]\nk = v\n", .parse(line: 1)),
  ]

  private static let booleans: [(text: String, value: Bool?)] = [
    ("yes", true),
    ("no", false),
    ("true", true),
    ("false", false),
    ("on", true),
    ("off", false),
    ("1", true),
    ("0", false),
    ("Yes", true),
    ("TRUE", true),
    ("On", true),
    ("YES", true),
    ("OFF", false),
    ("y", nil),
    ("t", nil),
    ("enabled", nil),
    ("2", nil),
    ("-1", nil),
    ("v", nil),
    ("TrUe", true),
    ("oFf", false),
    ("", nil),
    ("no ", false),
    ("\" yes \"", nil),
    ("\"yes\"", true),
    ("\"YES\"", true),
  ]

  private static let integers: [(text: String, value: Int?)] = [
    ("12", 12),
    ("-12", -12),
    ("+12", 12),
    ("0", 0),
    ("007", 7),
    ("1_0", 10),
    ("0x10", nil),
    ("12.0", nil),
    (" 12", 12),
    ("12 ", 12),
    ("1 2", nil),
    ("v", nil),
    ("_10", nil),
    ("10_", nil),
    ("1__0", nil),
    ("\u{FF11}\u{FF12}", 12),
    ("-0", 0),
    ("1_000", 1000),
    ("-", nil),
    ("+", nil),
    ("", nil),
    ("1-2", nil),
    ("\u{216B}", nil),
    ("\u{B2}", nil),
    ("\u{BD}", nil),
    ("\u{663}", 3),
    ("1\u{216B}", nil),
    ("\u{2160}", nil),
    ("\" 12 \"", 12),
    ("\"12\"", 12),
    ("\"\t12\"", 12),
    ("\" -12 \"", -12),
    ("\"1 2\"", nil),
    ("\"\u{A0}12\"", 12),
  ]

  private static let listed: [(text: String, values: [String])] = [
    ("x", ["x"]),
    ("x, y", ["x", "y"]),
    ("x,", ["x"]),
    (",", []),
    ("\"x, y\"", ["x, y"]),
    ("", [""]),
    ("x, y, z", ["x", "y", "z"]),
    ("\"\", x", ["", "x"]),
  ]

  /// Every configuration parses to the sections and values the reference read.
  func testFilesMatchTheReference() throws {
    for vector in Self.files {
      XCTAssertEqual(try RNGitConfigFile.parse(vector.text), vector.config, vector.name)
    }
  }

  /// Every configuration the reference refused is refused here, with the same error.
  func testRefusedFilesMatchTheReference() {
    for vector in Self.refused {
      XCTAssertThrowsError(try RNGitConfigFile.parse(vector.text), vector.name) { error in
        XCTAssertEqual(error as? RNGitConfigError, vector.error, vector.name)
      }
    }
  }

  /// Every value reads as the boolean the reference read, or as none.
  func testBooleansMatchTheReference() throws {
    for vector in Self.booleans {
      let section = try RNGitConfigFile.parse("[a]\nk = " + vector.text)
      XCTAssertEqual(section.section("a")?.bool("k"), vector.value, vector.text)
    }
  }

  /// Every value reads as the integer the reference read, or as none.
  func testIntegersMatchTheReference() throws {
    for vector in Self.integers {
      let section = try RNGitConfigFile.parse("[a]\nk = " + vector.text)
      XCTAssertEqual(section.section("a")?.int("k"), vector.value, vector.text)
    }
  }

  /// Every value reads as the list the reference read.
  func testListsMatchTheReference() throws {
    for vector in Self.listed {
      let section = try RNGitConfigFile.parse("[a]\nk = " + vector.text)
      XCTAssertEqual(section.section("a")?.list("k"), vector.values, vector.text)
    }
  }
}
