var inInput = false
var inAnswer = false

$(document).keydown(function(e) {
    var enter = 13
    var escape = 27
    switch (e.keyCode) {
        case enter:
            if (inInput) {
                send_values()
            } else if (inAnswer) {
                yes_func()
            }
            break
        case escape:
            if (inInput) {
                close_input()
            } else if (inAnswer) {
                no_func()
            }
            break
    }
})

$(function() {
    function display_input(bool) {
        if (bool) {
            $("#container").show()
        } else {
            $("#container").hide()
        }
    }
    function display_answer(bool) {
        if (bool) {
            $("#container2").show()
        } else {
            $("#container2").hide()
        }
    }

    display_input(false)
    display_answer(false)

    window.addEventListener('message', function(event) {
        if (event.data.type == "open_inputs") {
            if (event.data.status == true) {
                inInput = true
                display_input(true)
                $("#text_input").focus()
                set_input_info(event.data.title, event.data.subtext)
            } else {
                display_input(false)
                inInput = false
            }
        }
        if (event.data.type == "open_answer") {
            if (event.data.status == true) {
                inAnswer = true
                display_answer(true)
                $("#text_input").focus()
                set_input_answer(event.data.title, event.data.first, event.data.second)
            } else {
                display_answer(false)
                inAnswer = false
            }
        }
    })
})

function set_input_info(title, subtext) {
    document.getElementById("header").innerHTML = title
    var desc = document.getElementById("header_desc")
    if (desc) desc.innerHTML = subtext || ''
    // Re-apply i18n so button labels use the correct language
    if (window.JrsI18n && typeof JrsI18n.apply === 'function') JrsI18n.apply()
}

function set_input_answer(title, first, second) {
    document.getElementById("header2").innerHTML = title
    document.getElementById("button_2_ans").innerHTML = first
    document.getElementById("button_1_ans").innerHTML = second
}

function send_values() {
    if (document.getElementById("text_input").value === "") {
        document.getElementById("form_id").reset()
        $.post('https://jrs_core/jrs:close', JSON.stringify({ text: "close" }))
    } else {
        $.post('https://jrs_core/jrs:send', JSON.stringify({ text: document.getElementById("text_input").value }))
        document.getElementById("form_id").reset()
    }
    inInput = false
}

function close_input() {
    document.getElementById("form_id").reset()
    $.post('https://jrs_core/jrs:close', JSON.stringify({ text: "close" }))
    inInput = false
}

function yes_func() {
    document.getElementById("form_id").reset()
    $.post('https://jrs_core/jrs:yes', JSON.stringify({ text: "yes" }))
    inAnswer = false
}

function no_func() {
    document.getElementById("form_id").reset()
    $.post('https://jrs_core/jrs:no', JSON.stringify({ text: "no" }))
    inAnswer = false
}
