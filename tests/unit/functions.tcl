start_server {tags {"scripting"}} {
    test {FUNCTION - Basic usage} {
        r function create LUA test {return 'hello'}
        r fcall test 0
    } {hello}

    test {FUNCTION - Create an already exiting function raise error} {
        catch {
            r function create LUA test {return 'hello1'}
        } e
        set _ $e
    } {*Function already exists*}

    test {FUNCTION - Create function with unexisting engine} {
        catch {
            r function create bad_engine test {return 'hello1'}
        } e
        set _ $e
    } {*Engine not found*}

    test {FUNCTION - Test uncompiled script} {
        catch {
            r function create LUA test1 {bad script}
        } e
        set _ $e
    } {*Error compiling function*}

    test {FUNCTION - test replace argument} {
        r function create LUA test REPLACE {return 'hello1'}
        r fcall test 0
    } {hello1}

    test {FUNCTION - test replace argument with function creation failure keeps old function} {
         catch {r function create LUA test REPLACE {error}}
        r fcall test 0
    } {hello1}

    test {FUNCTION - test function delete} {
        r function delete test
        catch {
            r fcall test 0
        } e
        set _ $e
    } {*Function not found*}

    test {FUNCTION - test description argument} {
        r function create LUA test DESCRIPTION {some description} {return 'hello'}
        r function list
    } {{name test engine LUA description {some description}}}

    test {FUNCTION - test info specific function} {
        r function info test WITHCODE
    } {name test engine LUA description {some description} code {return 'hello'}}

    test {FUNCTION - test info without code} {
        r function info test
    } {name test engine LUA description {some description}}

    test {FUNCTION - test info on function that does not exists} {
        catch {
            r function info bad_function_name
        } e
        set _ $e
    } {*Function does not exists*}

    test {FUNCTION - test info with bad number of arguments} {
        catch {
            r function info test WITHCODE bad_arg
        } e
        set _ $e
    } {*wrong number of arguments*}

    test {FUNCTION - test fcall bad arguments} {
        catch {
            r fcall test bad_arg
        } e
        set _ $e
    } {*Bad number of keys provided*}

    test {FUNCTION - test fcall bad number of keys arguments} {
        catch {
            r fcall test 10 key1
        } e
        set _ $e
    } {*Number of keys can't be greater than number of args*}

    test {FUNCTION - test fcall negative number of keys} {
        catch {
            r fcall test -1 key1
        } e
        set _ $e
    } {*Number of keys can't be negative*}

    test {FUNCTION - test function delete on not exiting function} {
        catch {
            r function delete test1
        } e
        set _ $e
    } {*Function not found*}

    test {FUNCTION - test function kill when function is not running} {
        catch {
            r function kill
        } e
        set _ $e
    } {*No scripts in execution*}

    test {FUNCTION - test wrong subcommand} {
        catch {
            r function bad_subcommand
        } e
        set _ $e
    } {*Unknown subcommand*}

    test {FUNCTION - test loading from rdb} {
        r debug reload
        r fcall test 0
    } {hello}

    test {FUNCTION - test fcall_ro with write command} {
        r function create lua test REPLACE {return redis.call('set', 'x', '1')}
        catch { r fcall_ro test 0 } e
        set _ $e
    } {*Write commands are not allowed from read-only scripts*}

    test {FUNCTION - test fcall_ro with read only commands} {
        r function create lua test REPLACE {return redis.call('get', 'x')}
        r set x 1
        r fcall_ro test 0
    } {1}

    test {FUNCTION - test keys and argv} {
        r function create lua test REPLACE {return redis.call('set', KEYS[1], ARGV[1])}
        r fcall test 1 x foo
        r get x
    } {foo}

    test {FUNCTION - test command get keys on fcall} {
        r COMMAND GETKEYS fcall test 1 x foo
    } {x}

    test {FUNCTION - test command get keys on fcall_ro} {
        r COMMAND GETKEYS fcall_ro test 1 x foo
    } {x}

    test {FUNCTION - test function kill} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        r function create lua test REPLACE {local a = 1 while true do a = a + 1 end}
        $rd fcall test 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        assert_match {running_script {name test command {fcall test 0} duration_ms *} engines LUA} [r FUNCTION STATS]
        r function kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test script kill not working on function} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        r function create lua test REPLACE {local a = 1 while true do a = a + 1 end}
        $rd fcall test 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        catch {r script kill} e
        assert_match {BUSY*} $e
        r function kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test function kill not working on eval} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        $rd eval {local a = 1 while true do a = a + 1 end} 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        catch {r function kill} e
        assert_match {BUSY*} $e
        r script kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test function flush} {
        r function create lua test REPLACE {local a = 1 while true do a = a + 1 end}
        assert_match {{name test engine LUA description {}}} [r function list]
        r function flush
        assert_match {} [r function list]

        r function create lua test REPLACE {local a = 1 while true do a = a + 1 end}
        assert_match {{name test engine LUA description {}}} [r function list]
        r function flush async
        assert_match {} [r function list]

        r function create lua test REPLACE {local a = 1 while true do a = a + 1 end}
        assert_match {{name test engine LUA description {}}} [r function list]
        r function flush sync
        assert_match {} [r function list]
    }

    test {FUNCTION - test function wrong argument} {
        catch {r function flush bad_arg} e
        assert_match {*only supports SYNC|ASYNC*} $e

        catch {r function flush sync extra_arg} e
        assert_match {*wrong number of arguments*} $e
    }
}

start_server {tags {"scripting repl external:skip"}} {
    start_server {} {
        test "Connect a replica to the master instance" {
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 role] eq {slave} &&
                [string match {*master_link_status:up*} [r -1 info replication]]
            } else {
                fail "Can't turn the instance into a replica"
            }
        }

        test {FUNCTION - creation is replicated to replica} {
            r function create LUA test DESCRIPTION {some description} {return 'hello'}
            wait_for_condition 50 100 {
                [r -1 function list] eq {{name test engine LUA description {some description}}}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test {FUNCTION - call on replica} {
            r -1 fcall test 0
        } {hello}

        test {FUNCTION - delete is replicated to replica} {
            r function delete test
            wait_for_condition 50 100 {
                [r -1 function list] eq {}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test {FUNCTION - flush is replicated to replica} {
            r function create LUA test DESCRIPTION {some description} {return 'hello'}
            wait_for_condition 50 100 {
                [r -1 function list] eq {{name test engine LUA description {some description}}}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
            r function flush
            wait_for_condition 50 100 {
                [r -1 function list] eq {}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test "Disconnecting the replica from master instance" {
            r -1 slaveof no one
            # creating a function after disconnect to make sure function
            # is replicated on rdb phase
            r function create LUA test DESCRIPTION {some description} {return 'hello'}

            # reconnect the replica
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 role] eq {slave} &&
                [string match {*master_link_status:up*} [r -1 info replication]]
            } else {
                fail "Can't turn the instance into a replica"
            }
        }

        test "FUNCTION - test replication to replica on rdb phase" {
            r -1 fcall test 0
        } {hello}

        test "FUNCTION - test replication to replica on rdb phase info command" {
            r -1 function info test WITHCODE
        } {name test engine LUA description {some description} code {return 'hello'}}

        test "FUNCTION - create on read only replica" {
            catch {
                r -1 function create LUA test DESCRIPTION {some description} {return 'hello'}
            } e
            set _ $e
        } {*Can not create a function on a read only replica*}

        test "FUNCTION - delete on read only replica" {
            catch {
                r -1 function delete test
            } e
            set _ $e
        } {*Can not delete a function on a read only replica*}

        test "FUNCTION - function effect is replicated to replica" {
            r function create LUA test REPLACE {return redis.call('set', 'x', '1')}
            r fcall test 0
            assert {[r get x] eq {1}}
            wait_for_condition 50 100 {
                [r -1 get x] eq {1}
            } else {
                fail "Failed waiting function effect to be replicated to replica"
            }
        }

        test "FUNCTION - modify key space of read only replica" {
            catch {
                r -1 fcall test 0
            } e
            set _ $e
        } {*can't write against a read only replica*}
    }
}