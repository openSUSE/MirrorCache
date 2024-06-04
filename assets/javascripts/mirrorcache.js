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
    $('.folder-stats-servers-recent').text((data? data.recent : 'no data'));
    $('.folder-stats-servers-outdated').text(data? data.outdated: 'no data');
    $('.folder-stats-servers-not-scanned').text(data? data.not_scanned: 'no data');
    $('.folder-stats-last-sync').text(data? data.last_sync: 'no data');
    if (!data) {
        $('.folder-sync-job-position').text('no data');
    }  else if (data.sync_job_position) {
        $('.folder-sync-job-position').text('Position in queue: '.concat(data.sync_job_position));
    } else {
        $('.folder-sync-job-position').text('Not scheduled');
    }
    // setTimeout(function () { pollFolderStats(url) }, 3000);
  }); // ).fail( function () { setTimeout(function () { pollStats(url) }, 3000) });
}

function pollFolderJobStats(id) {
    var url = '/rest/folder_jobs/' + id;
    $.get(url).done(function (data) {
        $('.folder-job-sync-waiting-count').text(data.sync_waiting_count);
        $('.folder-job-sync-running-count').text(data.sync_running_count);
        $('.folder-job-scan-waiting-count').text(data.scan_waiting_count);
        $('.folder-job-scan-running-count').text(data.scan_running_count);
    });
}

function handleAjaxError(request, code, error) {
    if (request.responseJSON != undefined && request.responseJSON.error) {
        error += ': ' + request.responseJSON.error;
    } else if (request.responseText != undefined && request.responseText) {
        error += ': ' + request.responseText.error;
    }

    addFlash('danger', 'Error: ' + error);
}

function deleteAndRedirect(btn, redir) {
    $.ajax({
        url: btn.dataset.deleteurl,
        method: 'DELETE',
        dataType: 'json',
        success: function(data) {
            location.href = redir;
        },
        error: handleAjaxError,
    });
}

function sendPost(url, path) {
    $.ajax({
        url: url,
        method: 'POST',
        data: { path: path },
        dataType: 'json',
        success: function(data) {
            id = data.job_id;
            if (id) {
                location.href = '/minion/jobs?id='.concat(id);
            }
        },
        error: handleAjaxError,
    });
}

function fromNow(date) {
    const SECOND = 1000;
    const MINUTE = 60 * SECOND;
    const HOUR = 60 * MINUTE;
    const DAY = 24 * HOUR;
    const WEEK = 7 * DAY;
    const YEAR = 365 * DAY;
    const MONTH = YEAR / 12;
    const units = [
        { max: 30 * SECOND, divisor: 1, past1: 'just now', pastN: 'just now', future1: 'just now', futureN: 'just now' },
        { max: MINUTE, divisor: SECOND, past1: 'a second ago', pastN: '# seconds ago', future1: 'in a second', futureN: 'in # seconds' },
        { max: HOUR, divisor: MINUTE, past1: 'a minute ago', pastN: '# minutes ago', future1: 'in a minute', futureN: 'in # minutes' },
        { max: DAY, divisor: HOUR, past1: 'an hour ago', pastN: '# hours ago', future1: 'in an hour', futureN: 'in # hours' },
        { max: WEEK, divisor: DAY, past1: 'yesterday', pastN: '# days ago', future1: 'tomorrow', futureN: 'in # days' },
        { max: 4 * WEEK, divisor: WEEK, past1: 'last week', pastN: '# weeks ago', future1: 'in a week', futureN: 'in # weeks' },
        { max: YEAR, divisor: MONTH, past1: 'last month', pastN: '# months ago', future1: 'in a month', futureN: 'in # months' },
        { max: 100 * YEAR, divisor: YEAR, past1: 'last year', pastN: '# years ago', future1: 'in a year', futureN: 'in # years' },
        { max: 1000 * YEAR, divisor: 100 * YEAR, past1: 'last century', pastN: '# centuries ago', future1: 'in a century', futureN: 'in # centuries' },
        { max: Infinity, divisor: 1000 * YEAR, past1: 'last millennium', pastN: '# millennia ago', future1: 'in a millennium', futureN: 'in # millennia' },
    ];
    // ensure date is an object to safely use its functions
    date = (typeof date === 'object' ? date : new Date(date));
    // convert from utc time like this
    date = new Date(date.getTime() - date.getTimezoneOffset()*60*1000);

    const diff = Date.now() - date.getTime();
    const diffAbs = Math.abs(diff);
    for (const unit of units) {
        if (diffAbs < unit.max) {
            const isFuture = diff < 0;
            const x = Math.round(Math.abs(diff) / unit.divisor);
            if (x <= 1) return isFuture ? unit.future1 : unit.past1;
            return (isFuture ? unit.futureN : unit.pastN).replace('#', x);
        }
    }
};
