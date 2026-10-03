import datetime

from scripts.cache import Version, plan_package, split_package_name

NOW = datetime.datetime(2026, 10, 3, tzinfo=datetime.timezone.utc)


def v(id, *tags, days_old):
    return Version(id=id, tags=tuple(tags), created_at=NOW - datetime.timedelta(days=days_old))


def plan(versions, **kw):
    kw = {"now": NOW, "keep_days": 30, "keep_last": 2, **kw}
    return plan_package(versions, **kw)


def ids(versions):
    return sorted(x.id for x in versions)


def kept_ids(p):
    return sorted(x.id for x, _ in p.keep)


def test_keeps_latest_recent_current_and_newest_n():
    versions = [
        v(1, "aaaaaaaa-111111111111", days_old=100),
        v(2, "aaaaaaaa-222222222222", days_old=90),
        v(3, "latest", days_old=80),
        v(4, "aaaaaaaa-444444444444", days_old=70),
        v(5, "aaaaaaaa-555555555555", days_old=60),
        v(6, "aaaaaaaa-666666666666", days_old=50),
        v(7, "aaaaaaaa-777777777777", days_old=5),
    ]
    p = plan(versions, current_hashes=frozenset({"222222222222"}))
    # 7: recent; 3: latest; 2: current key; 7+6: newest 2 tagged
    assert kept_ids(p) == [2, 3, 6, 7]
    assert ids(p.delete) == [1, 4, 5]
    assert not p.delete_package


def test_current_hash_ignores_tool_version_prefix():
    versions = [v(1, "deadbeef-abcdefabcdef", days_old=200), v(2, "x-000000000000", days_old=1)]
    p = plan(versions, keep_last=1, current_hashes=frozenset({"abcdefabcdef"}))
    assert ids(p.delete) == []


def test_untagged_versions_do_not_count_toward_keep_last():
    versions = [
        v(1, days_old=40),  # untagged (superseded `latest` manifest)
        v(2, "a-111111111111", days_old=50),
        v(3, "a-222222222222", days_old=60),
        v(4, "a-333333333333", days_old=70),
    ]
    p = plan(versions)
    assert kept_ids(p) == [2, 3]
    assert ids(p.delete) == [1, 4]


def test_recent_untagged_versions_are_kept():
    p = plan([v(1, days_old=1), v(2, "a-111111111111", days_old=2)])
    assert ids(p.delete) == []


def test_never_deletes_last_version():
    p = plan([v(1, days_old=100), v(2, days_old=200)])
    assert kept_ids(p) == [1]
    assert ids(p.delete) == [2]


def test_removed_model_with_only_stale_versions_deletes_package():
    versions = [v(1, "latest", days_old=40), v(2, "a-111111111111", days_old=50)]
    p = plan(versions, model_exists=False)
    assert p.delete_package
    assert ids(p.delete) == [1, 2]
    assert p.keep == []


def test_removed_model_with_recent_version_is_pruned_normally():
    versions = [
        v(1, "a-111111111111", days_old=10),
        v(2, "a-222222222222", days_old=50),
        v(3, "a-333333333333", days_old=60),
    ]
    p = plan(versions, model_exists=False, keep_last=1)
    assert not p.delete_package
    assert kept_ids(p) == [1]
    assert ids(p.delete) == [2, 3]


def test_existing_model_with_only_stale_versions_keeps_newest():
    versions = [v(1, "a-111111111111", days_old=40), v(2, "a-222222222222", days_old=50)]
    p = plan(versions, keep_last=1)
    assert not p.delete_package
    assert kept_ids(p) == [1]


def test_empty_package():
    p = plan([])
    assert p.keep == [] and p.delete == [] and not p.delete_package


def test_split_package_name_only_matches_cache_namespaces():
    assert split_package_name("cad/renders/rack/bracket", "cad") == ("renders", "rack/bracket")
    assert split_package_name("cad/slices/a/b/c", "cad") == ("slices", "a/b/c")
    assert split_package_name("cad/ci", "cad") is None
    assert split_package_name("cad/toolchain/openscad", "cad") is None
    assert split_package_name("cad/renders/", "cad") is None
    assert split_package_name("other/renders/x/y", "cad") is None
