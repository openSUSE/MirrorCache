function setup_admin_user() {
    window.admin_user_table = $('#users').DataTable({
        order: [
            [0, 'asc']
        ]
    });

    $('#users').on('change', 'input[name="role"]:radio', function() {
        var username = $(this).parents('tr').find('.name').text();
        var role = $(this).attr('id');
        role = $('label[for="' + role + '"]').text();

        function findDefault(form) {
            return form.find('input[class="default"]').first();
        }

        function rollback(form) {
            findDefault(form).prop('checked', 'checked');
        }

        var form = $(this).parent('form');
        if (!confirm("Are you sure to put " + username + " into role: " + $.trim(role) + "?")) {
            rollback(form);
            return;
        }

        var data = form.serializeArray();
        var newRole = data[0].value;

        $.ajax({
            type: 'POST',
            url: form.attr('action'),
            data: jQuery.param(data),
            success: function(data) {
                findDefault(form).removeClass('default');
                form.find('input[value="' + newRole + '"]').addClass('default');
            },
            error: function(xhr, ajaxOptions, thrownError) {
                rollback(form);
                var error_message = 'An error occurred when changing the user role. ';
                if (xhr.responseJSON && xhr.responseJSON.error)
                    error_message += xhr.responseJSON.error;
                addFlash('danger', error_message);
            }
        });
    });

    window.deleteUser = function(id) {
        if (!confirm("Are you sure you want to delete this user?"))
            return;

        $.ajax({
            url: '/admin/user/' + id,
            method: 'DELETE',
            dataType: 'json',
            success: function() {
                addFlash('info', 'The user was deleted successfully.');
                window.admin_user_table.row($("#user_" + id)).remove().draw();
            },
            error: function(xhr, ajaxOptions, thrownError) {
                var error_message = 'An error occurred when deleting the user. ';
                if (xhr.responseJSON && xhr.responseJSON.error)
                    error_message += xhr.responseJSON.error;
                addFlash('danger', error_message);
            }
        });
    };
}
