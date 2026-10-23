-module(bigmeck_meck_tests).

-include_lib("eunit/include/eunit.hrl").

-doc """
Verify that a Meck expectation returns its configured value, validates
successfully, and restores the original function when the mock is unloaded.
""".
mock_lifecycle_test() ->
    ok = meck:new(bigmeck_test_target, [passthrough]),
    try
        ok = meck:expect(bigmeck_test_target, fun_a, 0, mocked),
        ?assertEqual(mocked, bigmeck_test_target:fun_a()),
        ?assert(meck:validate(bigmeck_test_target))
    after
        ok = meck:unload(bigmeck_test_target)
    end,
    ?assertEqual(original, bigmeck_test_target:fun_a()).

-doc """
Verify that Meck passthrough preserves the original behavior and arguments of
functions without an expectation while another function is mocked.
""".
passthrough_test() ->
    ok = meck:new(bigmeck_test_target, [passthrough]),
    try
        ok = meck:expect(bigmeck_test_target, fun_a, 0, mocked),
        ?assertEqual({original, value}, bigmeck_test_target:echo({original, value}))
    after
        ok = meck:unload(bigmeck_test_target)
    end.

-doc """
Verify that Meck rejects passthrough when the target's abstract code is missing.
Restore the original BEAM file after checking the failure.
""".
passthrough_requires_debug_info_test() ->
    Target = bigmeck_no_debug_info_target,
    BeamFile = code:which(Target),
    {ok, OriginalBeam} = file:read_file(BeamFile),
    {ok, {Target, StrippedBeam}} = beam_lib:strip(OriginalBeam),
    try
        ok = file:write_file(BeamFile, StrippedBeam),
        ?assertError(
            {abstract_code_not_found, Target},
            meck:new(Target, [passthrough, no_link])
        )
    after
        ok = file:write_file(BeamFile, OriginalBeam)
    end.
