%% Copyright (c) 2020, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

%% Much of this code is a duplicate of examples_SUITE
%% in the cowboy repository, with slight modifications.
%% @todo Refactor release handling code and move to ct_helper.

-module(upgrade_SUITE).
-compile(export_all).
-compile(nowarn_export_all).

-import(ct_helper, [doc/1]).

%% ct.

all() ->
	ct_helper:all(?MODULE).

init_per_suite(Config) ->
	%% Remove environment variables inherited from Erlang.mk.
	os:unsetenv("ERLANG_MK_TMP"),
	os:unsetenv("APPS_DIR"),
	os:unsetenv("DEPS_DIR"),
	os:unsetenv("ERL_LIBS"),
	os:unsetenv("CI_ERLANG_MK"),
	Config.

end_per_suite(_Config) ->
	ok.

%% Find GNU Make.

do_find_make_cmd() ->
	case os:getenv("MAKE") of
		false ->
			case os:find_executable("gmake") of
				false -> "make";
				Cmd   -> Cmd
			end;
		Cmd ->
			Cmd
	end.

%% Compile, start and stop releases.

do_get_paths(Example0) ->
	Example = atom_to_list(Example0),
	{ok, CWD} = file:get_cwd(),
	Dir = CWD ++ "/../../examples/" ++ Example,
	Rel = Dir ++ "/_rel/" ++ Example ++ "_example/bin/" ++ Example ++ "_example",
	Log = Dir ++ "/_rel/" ++ Example ++ "_example/log/erlang.log.1",
	{Dir, Rel, Log}.

do_compile_and_start(Example, Config) ->
	Make = do_find_make_cmd(),
	{Dir, Rel, _} = do_get_paths(Example),
	ct:log("~s~n", [os:cmd(Make ++ " -C " ++ Dir ++ " distclean")]),
	%% TERM=dumb disables relx coloring.
	ct:log("~s~n", [os:cmd(Make ++ " -C " ++ Dir ++ " TERM=dumb")]),
	ct:log("~s~n", [os:cmd(Rel ++ " stop")]),
	ct:log("~s~n", [os:cmd(Rel ++ " start")]),
	timer:sleep(2000),
	ok.

do_stop(Example) ->
	{Dir, Rel, Log} = do_get_paths(Example),
	ct:log("~s~n", [os:cmd("sed -i.bak s/\"2\"/\"1\"/ " ++ Dir ++ "/relx.config")]),
	ct:log("~s~n", [os:cmd(Rel ++ " stop")]),
	ct:log("~s~n", [element(2, file:read_file(Log))]),
	ok.

%% Tests.

upgrade_ranch_one_conn(Config) ->
	Example = tcp_echo,
	try
		do_use_ranch_previous(Example),
		%% @todo Set PROJECT_VERSION to ranch_prev.
		do_compile_and_start(Example, Config),
		%% @todo Here we need to establish a connection and check that it works.
			%% Here we must update the Ranch version to *master* since
			%% this is what we want to test.
		%% @todo Set PROJECT_VERSION to ranch_next if using a commit.
		do_use_ranch_commit(Example, "master"),
		do_build_relup(Example),
		do_upgrade(Example)
		%% @todo Check the Ranch version.
		%% @todo Check that our connection is still up.
		%% @todo Check that new connections still work.
		%% @todo Maybe downgrade too? Yup.
		%% @todo Check that our connection is still up.
		%% @todo Check that new connections still work.
	after
		do_stop(tcp_echo)
	end.

%% @todo upgrade_ranch_max_conn

%% When we are on a tag (git describe --exact-match succeeds),
%% we use the tag before that as a starting point. Otherwise
%% we use the most recent tag.
do_use_ranch_previous(Example) ->
	TagsOutput = os:cmd("git tag | tr - \~ | sort -V | tr \~ -"),
	ct:log("~s~n", [TagsOutput]),
	Tags = string:lexemes(TagsOutput, "\n"),
	DescribeOutput = os:cmd("git describe --exact-match || echo \"NOT_A_TAG\""),
	ct:log("~s~n", [DescribeOutput]),
	Prev = case DescribeOutput of
		"NOT_A_TAG\n" -> hd(lists:reverse(Tags));
		_ -> hd(tl(lists:reverse(Tags)))
	end,
	do_use_ranch_commit(Example, Prev).

%% Replace the current Ranch commit with the one given as argument.
do_use_ranch_commit(Example, Commit) ->
	{Dir, _, _} = do_get_paths(Example),
	ct:log("~s~n", [os:cmd(
		"sed -i.bak s/\"dep_ranch_commit = .*\"/\"dep_ranch_commit = "
		++ Commit ++ "\"/ " ++ Dir ++ "/Makefile"
	)]).

%% Remove Ranch and rebuild, this time generating a relup.
do_build_relup(Example) ->
	Make = do_find_make_cmd(),
	{Dir, _, _} = do_get_paths(Example),
	ct:log("~s~n", [os:cmd("rm -rf " ++ Dir ++ "/deps/ranch")]),
	ct:log("~s~n", [os:cmd("sed -i.bak s/\"1\"/\"2\"/ " ++ Dir ++ "/relx.config")]),
	%% We need Ranch to be fetched first in order to copy the current appup.
	ct:log("~s~n", [os:cmd(Make ++ " -C " ++ Dir ++ " deps")]),
	ct:log("~s~n", [os:cmd("cp " ++ Dir ++ "/../../ebin/ranch.appup "
		++ Dir ++ "/deps/ranch/ebin/")]),
	ct:log("~s~n", [os:cmd(Make ++ " -C " ++ Dir ++ " relup")]).

%% Copy the tarball in the correct location and upgrade.
do_upgrade(Example) ->
	ExampleStr = atom_to_list(Example),
	{Dir, Rel, _} = do_get_paths(Example),
%	ct:log("~s~n", [os:cmd("mkdir "
%		++ Dir ++ "/_rel/" ++ ExampleStr
%			++ "_example/releases/2/")]),
	ct:log("~s~n", [os:cmd("cp "
		++ Dir ++ "/_rel/" ++ ExampleStr
			++ "_example/" ++ ExampleStr ++ "_example-2.tar.gz "
		++ Dir ++ "/_rel/" ++ ExampleStr
			++ "_example/releases/2/" ++ ExampleStr ++ "_example.tar.gz")]),
	ct:log("~s~n", [os:cmd(Rel ++ " upgrade --no-permanent \"2\"")]).
