-- text / yes-no inputs on the JRS input + menu
function PassportTextInput(d, cb)
    CreateThread(function()
        local text = JRS.Input(d.title or '', d.desc or '')
        cb(text or 'DECLINE')
    end)
end

function PassportButtonInput(d, cb)
    CreateThread(function()
        local answer = JRS.Confirm({ header = d.title, content = d.desc,
            labels = { confirm = d.buttonparam1, cancel = d.buttonparam2 } })
        cb(answer == 'confirm' and 'ACCEPT' or 'DECLINE')
    end)
end
