def [=> strToInt] | _ := import("lib/atoi")
def [=> makeIRCClient, => connectIRCClient] := import("lib/irc/client",
    [=> Timer])
def [=> elementsOf] | _ := import("fun/elements")
def [=> makeMonteParser] | _ := import("lib/parsers/monte")

def webStarter():
    def [=> makeHTTPEndpoint] | _ := import("lib/http/server")
    def [
        => makeDebugResource,
        => makeResourceApp,
    ] | _ := import("lib/http/resource")
    def root := makeDebugResource(currentRuntime)
    def app := makeResourceApp(root)
    def endpoint := makeHTTPEndpoint(makeTCP4ServerEndpoint(8080))
    endpoint.listen(app)

def webVat := currentVat.sprout(`HTTP server`)
webVat.seed(webStarter)

def nick :Str := "airbrus"

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
    => &&_booleanFlow, => &&_iterWhile, => &&_validateFor, => &&__loop,
    => &&_switchFailed, => &&_makeVerbFacet,
    => &&_suchThat, => &&_matchSame, => &&_bind, => &&_quasiMatcher,
    => &&__auditedBy,
    # Superpowers.
    => &&M, => &&Ref, => &&eval, => &&help, => &&import, => &&b__quasiParser,
    => &&m__quasiParser, => &&simple__quasiParser, => &&term__quasiParser, => &&throw,
]

def baseEnvironment := [for `&&@name` => binding in (baseEnvironmentBindings) name => binding]

def performEval(text, env):
    try:
        def [result, newEnv] := eval.evalToPair(text, env)
        return [`$result`, newEnv]
    catch via (unsealException) [problem, _]:
        return [`$problem`, env]

def userEnvironments := [].asMap().diverge()

object handler:
    to getNick():
        return nick

    to loggedIn(client):
        client.join("#montebot")
        client.join("#monte")

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
            def userEnv := userEnvironments.fetch(user.getNick(),
                                                  fn {baseEnvironment})
            def [response, newEnv] := performEval(text, userEnv)
            userEnvironments[user.getNick()] := newEnv
            for line in response.split("\n"):
                client.say(channel, line)

        else if (message =~ `!@action @text`):
            switch (action):
                match =="parse":
                    def parser := makeMonteParser("<irc>")
                    parser.feedMany(text)
                    if (parser.failed()):
                        def failure := parser.getFailure()
                        client.say(channel, `Parse failure: $failure`)
                    else:
                        def result := parser.results()[0]
                        for line in `$result`.split("\n"):
                            client.say(channel, line)

                match _:
                    pass

        else if (message =~ `$nick: @action` ? (user.getNick() == "simpson")):
            switch (action):
                match `join @newChannel`:
                    client.say(channel, "Okay, joining " + newChannel)
                    client.join(newChannel)

                match `speak`:
                    client.say(channel, "Hi there!")

                match `quit`:
                    client.say(channel, "Okay, bye!")
                    client.quit("ma'a tarci pulce")

                match `kill`:
                    client.say(channel,
                        `${user.getNick()}: Sorry, I don't know how to do that. Yet.`)

                match `list @otherChannel`:
                    escape ej:
                        def users := [for k => _ in (client.getUsers(otherChannel, ej)) k]
                        client.say(channel, " ".join(users))
                    catch _:
                        client.say(channel, `I can't see into $otherChannel`)

                match `in @{via (strToInt) seconds} say @utterance`:
                    when (Timer.fromNow(seconds)) ->
                        client.say(channel,
                            `${user.getNick()}: Alarm: "$utterance"`)

                match `elements @word`:
                    client.say(channel, `Elements: ${elementsOf(word)}`)

                match _:
                    client.say(channel, `${user.getNick()}: I don't understand.`)

def client := makeIRCClient(handler)
def ep := makeTCP4ClientEndpoint("irc.freenode.net", 6667)
connectIRCClient(client, ep)
