function setupForAll() {
    $('[data-toggle="tooltip"]').tooltip({ html: true });
    $('[data-toggle="popover"]').popover({ html: true });
    // workaround for popover with hover on text for firefox
    $('[data-toggle="popover"]').on('click', function(e) {
         e.target.closest('a').focus();
    });
}

function addFlash(status, text, container) {
    // add flash messages by default on top of the page
    if (!container) {
        container = $('#flash-messages');
    }

    var div = $('<div class="alert alert-primary alert-dismissible fade show" role="alert"></div>');
    if (typeof text === 'string') {
        div.append($('<span>' + text + '</span>'));
    } else {
        div.append(text);
    }
    div.append($('<button type="button" class="close" data-dismiss="alert" aria-label="Close"><span aria-hidden="true">&times;</span></button>'));
    div.addClass('alert-' + status);
    container.append(div);
    return div;
}

function addUniqueFlash(status, id, text, container) {
    // add hash to store present flash messages
    if (!window.uniqueFlashMessages) {
        window.uniqueFlashMessages = {};
    }
    // update existing flash message
    var existingFlashMessage = window.uniqueFlashMessages[id];
    if (existingFlashMessage) {
        existingFlashMessage.find('span').first().text(text);
        return;
    }

    var msgElement = addFlash(status, text, container);
    window.uniqueFlashMessages[id] = msgElement;
    msgElement.on('closed.bs.alert', function() {
        delete window.uniqueFlashMessages[id];
    });
}

function parseQueryParams() {
    var params = {};
    $.each(window.location.search.substr(1).split('&'), function(index, param) {
        var equationSignIndex = param.indexOf('=');
        var key, value;
        if (equationSignIndex < 0) {
            key = decodeURIComponent(param);
            value = undefined;
        } else {
            key = decodeURIComponent(param.substr(0, equationSignIndex));
            value = decodeURIComponent(param.substr(equationSignIndex + 1));
        }
        if (Array.isArray(params[key])) {
            params[key].push(value);
        } else {
            params[key] = [value];
        }
    });
    return params;
}

function updateQueryParams(params) {
    if (!history.replaceState) {
        return; // skip if not supported
    }
    var search = [];
    $.each(params, function(key, values) {
        $.each(values, function(index, value) {
            if (value === undefined) {
                search.push(encodeURIComponent(key));
            } else {
                search.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
            }
        });
    });
    history.replaceState({}, document.title, window.location.pathname + '?' + search.join('&'));
}

// reloads the page - this wrapper exists to be able to disable the reload during tests
function reloadPage() {
    location.reload();
}

function htmlEscape(str) {
    if (str === undefined || str === null) {
        return '';
    }
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function pollFolderStats(url) {
  url = url.concat('?status=all');
  $.get(url).done(function (data) {
    $('.folder-stats-servers-synced').text(data.synced);
    $('.folder-stats-servers-outdated').text(data.outdated);
    $('.folder-stats-servers-missing').text(data.missing);
    $('.folder-stats-last-sync').text(data.last_sync);
    // setTimeout(function () { pollFolderStats(url) }, 3000);
  }); // ).fail( function () { setTimeout(function () { pollStats(url) }, 3000) });
}
