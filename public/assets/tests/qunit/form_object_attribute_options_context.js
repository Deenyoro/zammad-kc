// Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

/* eslint-disable zammad/zammad-detect-translatable-string */

// First, let's verify that the field type is available
QUnit.test("object_attribute_options_context field type availability", assert => {
  assert.ok(App.UiElement.object_attribute_options_context, 'object_attribute_options_context field type should be available')
  assert.ok(App.UiElement.object_attribute_options_context.render, 'object_attribute_options_context render method should be available')
});

// object_attribute_options_context
QUnit.test("object_attribute_options_context check", assert => {

  $('#forms').append('<hr><h1>object_attribute_options_context check</h1><form id="form1"></form>')
  var el = $('#form1')

  // Mock the related object attribute that would be fetched
  var mockRelatedAttribute = {
    display: 'Priority',
    options: {
      '1': '1 low',
      '2': '2 normal',
      '3': '3 high',
      '4': '4 urgent'
    }
  }

  // Mock the fetchObjectManagerAttribute method
  var originalFetchMethod = App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = function(_attribute) {
    return mockRelatedAttribute
  }

  // Mock the ApplicationTreeSelect render method to return a simple element
  var originalTreeSelectRender = App.UiElement.ApplicationTreeSelect.render
  App.UiElement.ApplicationTreeSelect.render = function(_attribute) {
    return $('<div class="js-shadow"><select><option value="1">1 low</option><option value="2">2 normal</option><option value="3">3 high</option><option value="4">4 urgent</option></select></div>')
  }

  var defaults = {
    object_attribute_options_context1: { '2': '' },
    object_attribute_options_context2: {},
  }

  new App.ControllerForm({
    el:        el,
    model:     {
      configure_attributes: [
        {
          name:    'object_attribute_options_context1',
          display: 'ObjectAttributeOptionsContext1',
          tag:     'object_attribute_options_context',
          object_attribute_object: 'Ticket',
          object_attribute_name: 'priority_id',
          limit_label: 'Limit to selected options',
          table_label: 'Selected Options',
          limit_description: 'When enabled, only selected options will be available',
          default: defaults['object_attribute_options_context1'],
          null:    true
        },
        {
          name:    'object_attribute_options_context2',
          display: 'ObjectAttributeOptionsContext2',
          tag:     'object_attribute_options_context',
          object_attribute_object: 'Ticket',
          object_attribute_name: 'priority_id',
          limit_label: 'Limit to selected options',
          table_label: 'Selected Options',
          limit_description: 'When enabled, only selected options will be available',
          default: defaults['object_attribute_options_context2'],
          null:    true
        },
      ]
    },
    autofocus: true
  })

  var params = App.ControllerForm.params(el)
  var test_params = {
    object_attribute_options_context1: { '2': '' },
    object_attribute_options_context2: {},
  }
  assert.deepEqual(params, test_params, 'form param check')

  // Use data-attribute-name selector to find the specific fields
  var $field1 = el.find('[data-attribute-name="object_attribute_options_context1"]')
  var $field2 = el.find('[data-attribute-name="object_attribute_options_context2"]')

  assert.equal($field1.length, 1, 'field1 should be rendered')
  assert.equal($field2.length, 1, 'field2 should be rendered')

  // Check if the hidden inputs exist
  assert.equal($field1.find('.js-objectAttributeOptionsContext').length, 1, 'hidden input should exist in field1')
  assert.equal($field2.find('.js-objectAttributeOptionsContext').length, 1, 'hidden input should exist in field2')

  // Test that the limit toggle is checked when there are selected options
  assert.equal($field1.find('input[type="checkbox"]').is(':checked'), true, 'limit toggle should be checked when options are selected')
  assert.equal($field2.find('input[type="checkbox"]').is(':checked'), false, 'limit toggle should be unchecked when no options are selected')

  // Test that the list container is visible when limit is active
  assert.equal($field1.find('.js-objectAttributeOptionsContextListContainer').hasClass('hide'), false, 'list container should be visible when limit is active')
  assert.equal($field2.find('.js-objectAttributeOptionsContextListContainer').hasClass('hide'), true, 'list container should be hidden when limit is inactive')

  // Test that selected options are displayed in the table
  var $table1 = $field1.find('.js-objectAttributeOptionsContextList')
  assert.equal($table1.find('tr[data-id="2"]').length, 1, 'selected option should be displayed in table')
  assert.equal($table1.find('tr[data-id="2"] td:first-child').text(), '2 normal', 'selected option should show correct display text')

  // Test toggling the limit switch
  $field2.find('input[type="checkbox"]').trigger('click')
  assert.equal($field2.find('.js-objectAttributeOptionsContextListContainer').hasClass('hide'), false, 'list container should be visible after enabling limit')

  // Test that the hidden input is cleared when limit is disabled
  $field2.find('input[type="checkbox"]').trigger('click')
  assert.equal($field2.find('.js-objectAttributeOptionsContextListContainer').hasClass('hide'), true, 'list container should be hidden after disabling limit')
  assert.equal($field2.find('.js-objectAttributeOptionsContext').val(), '{}', 'hidden input should be cleared when limit is disabled')

  // Restore original methods
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = originalFetchMethod
  App.UiElement.ApplicationTreeSelect.render = originalTreeSelectRender

});

QUnit.test("object_attribute_options_context with relation check", assert => {

  $('#forms').append('<hr><h1>object_attribute_options_context with relation check</h1><form id="form2"></form>')
  var el = $('#form2')

  // Mock the related object attribute with relation
  var mockRelatedAttribute = {
    display: 'Group',
    relation: 'Group'
  }

  // Mock the fetchObjectManagerAttribute method
  var originalFetchMethod = App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = function(_attribute) {
    return mockRelatedAttribute
  }

  // Mock the Group model for relation testing
  var originalGroupSearch = App.Group.search
  App.Group.search = function(_params) {
    return [
      { id: 1, displayName: function() { return 'Users' } },
      { id: 2, displayName: function() { return 'Support' } },
      { id: 3, displayName: function() { return 'Admin' } }
    ]
  }

  // Mock the ApplicationTreeSelect render method
  var originalTreeSelectRender = App.UiElement.ApplicationTreeSelect.render
  App.UiElement.ApplicationTreeSelect.render = function(_attribute) {
    return $('<div class="js-shadow"><select><option value="1">Users</option><option value="2">Support</option><option value="3">Admin</option></select></div>')
  }

  var defaults = {
    object_attribute_options_context3: { '1': '' },
  }

  new App.ControllerForm({
    el:        el,
    model:     {
      configure_attributes: [
        {
          name:    'object_attribute_options_context3',
          display: 'ObjectAttributeOptionsContext3',
          tag:     'object_attribute_options_context',
          object_attribute_object: 'Ticket',
          object_attribute_name: 'group_id',
          limit_label: 'Limit to selected groups',
          table_label: 'Selected Groups',
          limit_description: 'When enabled, only selected groups will be available',
          default: defaults['object_attribute_options_context3'],
          null:    true
        },
      ]
    },
    autofocus: true
  })

  var params = App.ControllerForm.params(el)
  var test_params = {
    object_attribute_options_context3: { '1': '' },
  }
  assert.deepEqual(params, test_params, 'form param check with relation')

  // Test that the relation-based options are available in the dropdown
  var $field = el.find('[data-attribute-name="object_attribute_options_context3"]')
  var $dropdown = $field.find('.js-shadow')

  // The dropdown should be rendered with relation options
  assert.equal($dropdown.length, 1, 'dropdown should be rendered for relation-based field')

  // Restore original methods
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = originalFetchMethod
  App.Group.search = originalGroupSearch
  App.UiElement.ApplicationTreeSelect.render = originalTreeSelectRender

});

QUnit.test("object_attribute_options_context with tree options check", assert => {

  $('#forms').append('<hr><h1>object_attribute_options_context with tree options check</h1><form id="form3"></form>')
  var el = $('#form3')

  // Mock the related object attribute with tree options
  // For tree options, we need to provide the flattened options that buildFlatOptions would produce
  var mockRelatedAttribute = {
    display: 'Category',
    options: [
      { value: 'Hardware', name: 'Hardware' },
      { value: 'Software', name: 'Software', children: [
        { value: 'Software::Windows', name: 'Windows' },
        { value: 'Software::Linux', name: 'Linux' }
      ]}
    ]
  }

  // Mock the fetchObjectManagerAttribute method
  var originalFetchMethod = App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = function(_attribute) {
    return mockRelatedAttribute
  }

  // Mock the ApplicationTreeSelect render method
  var originalTreeSelectRender = App.UiElement.ApplicationTreeSelect.render
  App.UiElement.ApplicationTreeSelect.render = function(_attribute) {
    return $('<div class="js-shadow"><select><option value="Hardware">Hardware</option><option value="Software::Windows">Software › Windows</option><option value="Software::Linux">Software › Linux</option></select></div>')
  }

  var defaults = {
    object_attribute_options_context4: { 'Software::Windows': '' },
  }

  new App.ControllerForm({
    el:        el,
    model:     {
      configure_attributes: [
        {
          name:    'object_attribute_options_context4',
          display: 'ObjectAttributeOptionsContext4',
          tag:     'object_attribute_options_context',
          object_attribute_object: 'Ticket',
          object_attribute_name: 'category_id',
          limit_label: 'Limit to selected categories',
          table_label: 'Selected Categories',
          limit_description: 'When enabled, only selected categories will be available',
          default: defaults['object_attribute_options_context4'],
          null:    true
        },
      ]
    },
    autofocus: true
  })

  var params = App.ControllerForm.params(el)
  var test_params = {
    object_attribute_options_context4: { 'Software::Windows': '' },
  }
  assert.deepEqual(params, test_params, 'form param check with tree options')

  // Test that the tree option is displayed correctly (with › separator)
  var $field = el.find('[data-attribute-name="object_attribute_options_context4"]')
  var $table = $field.find('.js-objectAttributeOptionsContextList')

  assert.equal($table.find('tr[data-id="Software::Windows"]').length, 1, 'tree option should be displayed in table')
  assert.equal($table.find('tr[data-id="Software::Windows"] td:first-child').text(), 'Software › Windows', 'tree option should show flattened display text')

  // Restore original method
  App.UiElement.object_attribute_options_context.fetchObjectManagerAttribute = originalFetchMethod
  App.UiElement.ApplicationTreeSelect.render = originalTreeSelectRender

});
