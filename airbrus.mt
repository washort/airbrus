imports
exports (main)

def [=> makePumpTube :DeepFrozen] | _ := import.script("lib/tubes/pumpTube")
def [=> makeUTF8DecodePump :DeepFrozen,
     => makeUTF8EncodePump :DeepFrozen] | _ := import.script("lib/tubes/utf8")


def chooseAddress(addrs) :NullOk[Bytes] as DeepFrozen:
    for addr in addrs:
        if (addr.getFamily() == "INET" && addr.getSocketType() == "stream"):
            return addr.getAddress()


def partition(iterable, pred) as DeepFrozen:
    def yes := [].diverge()
    def no := [].diverge()
    for i in iterable:
        pred(i).pick(yes, no).push(i)
    return [yes.snapshot(), no.snapshot()]


def parseArguments([processName, scriptName] + var argv) as DeepFrozen:
    var channels :List[Str] := []
    var nick :Str := "airbrus"

    while (argv.size() > 0):
        switch (argv):
            match [=="-n", n] + tail:
                traceln(`Using nick '$nick'`)
                nick := n
                argv := tail
            match [channel] + tail:
                traceln(`Adding channel '$channel'`)
                channels with= (channel)
                argv := tail

    return object configuration:
        to channels() :List[Str]:
            return channels

        to nick() :Str:
            return nick


def makeAirbrusHelp(sayer) as DeepFrozen:
    return def airbrusHelp(specimen):
        def quoted := M.toQuote(specimen)
        def iface := specimen._getAllegedInterface()
        sayer(`Object: $quoted Interface: $iface`)


# def dumpTodo(drain, todo :Map[Str, List[Str]]) as DeepFrozen:
def dumpTodo(drain, todo) as DeepFrozen:
    traceln(`entered dumpTodo`)
    for k => v in todo:
        traceln(`dumping $k => $v`)
        drain<-receive(`$k:$\n`)
        for item in v:
            drain<-receive(` * $item$\n`)

def loadTodo(fount) as DeepFrozen:
    def [p, r] := Ref.promise()
    var currentKey :Str := "mlatu"
    def items := ["mlatu" => ["ko melbi"].diverge()].diverge()

    object todoDrain:
        to flowingFrom(fount):
            return todoDrain

        to receive(data):
            switch (data):
                match ` * @item`:
                    items[currentKey].push(item)
                match `@key:`:
                    currentKey := key
                    items[currentKey] := [].diverge()
                match line:
                    r.smash(`Couldn't load todo line: $line`)

        to flowStopped(reason):
            r.resolve(items)

        to flowAborted(reason):
            r.smash(`Couldn't load todo: $reason`)

    return p


def main(=> bench, => unittest, => Timer,
         => currentProcess, => currentRuntime, => currentVat,
         => getAddrInfo,
         => makeFileResource,
         => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint,
         => unsealException) as DeepFrozen:
    def [=> strToInt] | _ := import.script("lib/atoi")
    def [=> makeIRCClient, => connectIRCClient] := import.script("lib/irc/client",
        [=> &&Timer])
    def [=> makeMonteParser] | _ := import.script("lib/parsers/monte",
                                                  [=> &&bench])
    def [=> makeSplitPump :DeepFrozen] | _ := import("lib/tubes/splitPump",
                                                     [=> unittest])
    def [=> chain] := import.script("lib/tubes/chain")


    def makeLineTube() as DeepFrozen:
        return makePumpTube(makeSplitPump(b`$\n`))

    var todoList := [].asMap().diverge()
    def todoFile := makeFileResource("todo.list")
    def putTodo():
        def drain := chain([
            makePumpTube(makeUTF8EncodePump()),
            todoFile.openDrain(),
        ])
        dumpTodo(drain, todoList)
        drain<-flowStopped("Finished dumping todo")
    def getTodo():
        def fount := chain([
            todoFile.openFount(),
            makeLineTube(),
            makePumpTube(makeUTF8DecodePump()),
        ])
        def p := loadTodo(fount)
        when (p) ->
            traceln("Loaded")
            todoList := p
        catch problem:
            traceln(`Problem loading todo: $problem`)
    getTodo()
    def putTodoItem(nick, item):
        if (todoList.contains(nick)):
            todoList[nick].push(item)
        else:
            todoList[nick] := [item].diverge()
        putTodo()
    def showTodoItems(name, sayer):
        def items :List[Str] := todoList.fetch(name, fn {[]}).snapshot()
        if (items.size() == 0):
            sayer(`$name has nothing to do.`)
        else:
            sayer(`$name should do:`)
            for item in items:
                sayer(`• $item`)
    def removeTodoItem(name, needle, sayer):
        if (todoList.contains(name)):
            def items := todoList[name]
            def [crossedOff,
                 remaining] := partition(items, fn s {s =~ `@_$needle@_`})
            switch (crossedOff):
                match []:
                    sayer(`I'm not seeing it on $name's list…`)
                match [single]:
                    todoList[name] := remaining.diverge()
                    putTodo()
                    sayer(`Crossed off "$single". Good work!`)
                match several:
                    sayer(`I found a couple things; which one did you mean?`)
                    for item in several:
                        sayer(`• $item`)
        else:
            sayer(`But $name's list is empty.`)

    def config := parseArguments(currentProcess.getArguments())

    def webStarter():
        def [=> tag] | _ := import.script("lib/http/tag")
        def [
            => makeDebugResource,
            => makeResource,
            => makeResourceApp,
            => notFoundResource,
            => smallBody,
        ] | _ := import("lib/http/resource")

        def rootWorker(resource, verb, headers):
            return smallBody(`<ul>
                <li><a href="/debug">debug</a></li>
            </ul>`)

        def root := makeResource(rootWorker,
                                 ["debug" => makeDebugResource(currentRuntime)])

        def [=> makeHTTPEndpoint] | _ := import.script("lib/http/server")
        def app := makeResourceApp(root)
        def endpoint := makeHTTPEndpoint(makeTCP4ServerEndpoint(8080))
        endpoint.listen(app)

    def webVat := currentVat.sprout(`HTTP server`)
    webVat.seed(webStarter)

    def nick :Str := config.nick()

    def crypt := currentRuntime.getCrypt()
    def baseEnvironmentBindings := [
        => &&null, => &&true, => &&false, => &&Infinity, => &&NaN,
        => &&__makeList, => &&__makeMap, => &&__makeMessageDesc, => &&_makeOrderedSpace,
        => &&__makeParamDesc, => &&__makeProtocolDesc, => &&__makeString,
        => &&__equalizer, => &&_comparer,
        => &&_accumulateList, => &&_accumulateMap,
        => &&__slotToBinding,
        => &&Any, => &&Bool, => &&Bytes, => &&Char, => &&DeepFrozen, => &&Double, => &&Empty,
        => &&Int, => &&List, => &&Map, => &&Near, => &&NullOk, => &&Same, => &&Selfless,
        => &&Set, => &&Str, => &&SubrangeGuard, => &&Void,
        => &&_splitList, => &&_mapEmpty, => &&_mapExtract,
        => &&_booleanFlow, => &&_iterForever, => &&_validateFor, => &&__loop,
        => &&_switchFailed, => &&_makeVerbFacet,
        => &&_suchThat, => &&_matchSame, => &&_bind, => &&_quasiMatcher,
        => &&__auditedBy,
        # Superpowers.
        => &&M, => &&Ref, => &&eval, => &&import, => &&b__quasiParser,
        => &&m__quasiParser, => &&simple__quasiParser, => &&throw,
        => &&getAddrInfo,
        # Crypto services.
        => &&crypt,
    ]

    def baseEnv := [for `&&@name` => binding in (baseEnvironmentBindings) name => binding]

    def performEval(text, env, sayer):
        try:
            def [result, newEnv] := eval.evalToPair(text, env)
            # If the result is eventual, then don't say it yet, but set up a
            # callback for when it resolves.
            if (Ref.isResolved(result)):
                sayer(M.toQuote(result))
            else:
                sayer("I'll let you know when that's ready.")
                when (result) ->
                    sayer(`Here you are: ${M.toQuote(result)}`)
                catch problem:
                    sayer(`There was a problem: ${M.toQuote(problem)}`)
            return newEnv
        catch via (unsealException) [problem, _]:
            sayer(`Exception: $problem`)
            return env

    def userEnvironments := [].asMap().diverge()

    object handler:
        to getNick():
            return nick

        to loggedIn(client):
            for channel in config.channels():
                traceln(`Joining #$channel...`)
                client.join(`#$channel`)

        to ctcp(client, user, message):
            switch (message):
                match =="VERSION":
                    def name := "Airbrus"
                    def version := "0.0.1"
                    def environment := "Written in Monte, running on Typhon"
                    client.ctcp(user.getNick(), `VERSION $name ($version): $environment`)
                match =="SOURCE":
                    def url := "https://github.com/MostAwesomeDude/airbrus"
                    client.ctcp(user.getNick(), `SOURCE $url`)

                match _:
                    traceln(`Unknown CTCP $message`)

        to privmsg(client, user, channel, message):
            if (message =~ `> @text`):
                # Customize help so that its output doesn't get quoted.
                def help := makeAirbrusHelp(fn s {client.say(channel, s)})
                def instanceEnv := ["help" => &&help]
                def userEnv := userEnvironments.fetch(user.getNick(),
                                                      fn {baseEnv | instanceEnv})
                def sayer(s :Str):
                    for line in s.split("\n"):
                        client.say(channel, line)
                def newEnv := performEval(text, userEnv, sayer)
                userEnvironments[user.getNick()] := newEnv

            else if (message =~ `$nick: @action`):
                switch (action):
                    match `speak`:
                        client.say(channel, "Hi there!")

                    match `quit` ? (user.getNick() == "simpson"):
                        client.say(channel, "Okay, bye!")
                        client.quit("ma'a tarci pulce")

                    match `kill`:
                        client.say(channel,
                            `${user.getNick()}: Sorry, I don't know how to do that. Yet.`)

                    match `in @{via (strToInt) seconds} say @utterance`:
                        when (Timer.fromNow(seconds)) ->
                            client.say(channel,
                                `${user.getNick()}: "$utterance"`)

                    match `todo`:
                        showTodoItems(user.getNick(),
                                      fn s {client.say(channel, s)})

                    match `todo @name`:
                        if (name == ""):
                            # They typed "todo ".
                            showTodoItems(user.getNick(),
                                          fn s {client.say(channel, s)})
                        else:
                            showTodoItems(name, fn s {client.say(channel, s)})

                    match `I should @things`:
                        putTodoItem(user.getNick(), things)
                        client.say(channel,
                                   `${user.getNick()}: I'm holding you to that.`)

                    match `@name should @things`:
                        putTodoItem(name, things)
                        client.say(channel,
                                   `$name: I've put that on your list.`)

                    match `I did @needle`:
                        def name := user.getNick()
                        removeTodoItem(name, needle,
                                       fn s {client.say(channel, s)})

                    match `@name did @needle`:
                        removeTodoItem(name, needle,
                                       fn s {client.say(channel, s)})

                    match _:
                        client.say(channel, `${user.getNick()}: I don't understand.`)

    def addrs := getAddrInfo(b`irc.freenode.net`, b``)
    when (addrs) ->
        def address := chooseAddress(addrs)
        if (address == null):
            traceln("Couldn't choose an address to connect to!")

        def client := makeIRCClient(handler)
        def ep := makeTCP4ClientEndpoint(address, 6667)
        connectIRCClient(client, ep)

    return 0
