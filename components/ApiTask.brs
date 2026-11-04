sub init()
    m.top.functionName = "doRequest"
end sub

sub doRequest()
    url = CreateObject("roUrlTransfer")
    base = m.top.baseUrl
    full = base + "/" + m.top.method
    sep = "?"
    q = normalizeObject(m.top.query)
    isPost = m.top.tag = "resolve" or m.top.method = "resolveLive"

    if q <> invalid and not isPost
        for each key in q
            full = full + sep + url.Escape(key) + "=" + url.Escape(q[key].toStr())
            sep = "&"
        end for
    end if

    url.SetUrl(full)
    print q
    print full
    url.SetCertificatesFile("common:/certs/ca-bundle.crt")
    url.InitClientCertificates()
    url.EnableEncodings(true)

    if isPost
        url.SetRequest("POST")
        url.AddHeader("Content-Type", "application/json")
        url.AddHeader("Accept", "application/json")

        requestBody = FormatJson(q)
        port = CreateObject("roMessagePort")
        url.SetMessagePort(port)
        if not url.AsyncPostFromString(requestBody)
            res = { returnValue: false, errorText: "No se pudo iniciar el POST" }
        else
            event = Wait(30000, port)
            if event = invalid
                url.AsyncCancel()
                res = { returnValue: false, errorText: "Tiempo de espera agotado en el POST" }
            else if type(event) <> "roUrlEvent"
                res = { returnValue: false, errorText: "Evento inesperado durante el POST" }
            else
                responseCode = event.GetResponseCode()
                responseBody = event.GetString()
                print responseBody
                res = invalid
                if responseCode >= 200 and responseCode < 300
                    if type(responseBody) = "String" and responseBody <> "" then res = ParseJson(responseBody)
                    if res = invalid
                        res = { returnValue: false, errorText: "Sin respuesta válida del servidor" }
                    end if
                else
                    res = { returnValue: false, errorText: "Error HTTP " + responseCode.ToStr() }
                end if
            end if
        end if
    else
        body = url.GetToString()
        res = invalid
        if type(body) = "String" and body <> "" then res = ParseJson(body)
        if res = invalid
            res = { returnValue: false, errorText: "Sin respuesta del servidor" }
        end if
    end if
    res.tag = m.top.tag
    m.top.result = res
end sub

function normalizeObject(query as object) as object
    if query = invalid then return {}

    newObject = {}
    for each key in query
        jsonKey = key
        lowerKey = LCase(key)
        if lowerKey = "contentid" then
            jsonKey = "contentId"
        else if lowerKey = "seriescontentid" then
            jsonKey = "seriesContentId"
        else if lowerKey = "pagenum" then
            jsonKey = "pageNum"
        else if lowerKey = "columnid" then
            jsonKey = "columnId"
        else if lowerKey = "pagesize" then
            jsonKey = "pageSize"
        else if lowerKey = "channelcode" then
            jsonKey = "channelCode"
        end if
        newObject[jsonKey] = query[key]
    end for

    return newObject
end function
