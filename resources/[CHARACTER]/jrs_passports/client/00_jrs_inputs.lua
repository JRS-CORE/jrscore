-- jrs_passports | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
-- jrs_passports | client: the text and yes/no questions, on the JRS input and confirm windows

-- asks for a text; the callback gets what was typed, or 'DECLINE'
function PassportTextInput(question, done)
    CreateThread(function()
        done(JRS.Input(question.title or '', question.desc or '') or 'DECLINE')
    end)
end

-- asks yes or no; the callback gets 'ACCEPT' or 'DECLINE'
function PassportButtonInput(question, done)
    CreateThread(function()
        local answer = JRS.Confirm({
            header = question.title, content = question.desc,
            labels = { confirm = question.buttonparam1, cancel = question.buttonparam2 },
        })
        done(answer == 'confirm' and 'ACCEPT' or 'DECLINE')
    end)
end
