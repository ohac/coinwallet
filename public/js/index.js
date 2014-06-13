$(function(){
  $('span.balance').each(function(){
    var id = $(this).attr('id');
    var coinid = id.split('_')[1];
    $.ajax({
      url: '/api/v1/' + coinid + '/balance',
      cache: false,
      dataType: 'json',
      success: function(json){
        var balance = json['balance'];
        $('#' + id).text(balance.toFixed(4));
      }
    });
  });
});
